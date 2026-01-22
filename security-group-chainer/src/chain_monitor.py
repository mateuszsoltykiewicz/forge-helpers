"""Chain monitor - async monitoring and rule creation."""

import asyncio
import time
from typing import List, Dict, Any
from aws_client import AWSSecurityGroupClient
from circuit_breaker import CircuitBreaker


class ChainMonitor:
    """
    Monitors security group creation and creates chain rules.
    
    Workflow:
    1. Wait for both master and slave tier security groups to exist
    2. Create ingress/egress rules between them
    3. Report results
    """
    
    def __init__(
        self,
        name: str,
        master_tier: str,
        slave_tier: str,
        ports: List[int],
        protocol: str,
        bidirectional: bool,
        vpc_id: str,
        aws_client: AWSSecurityGroupClient,
        circuit_breaker: CircuitBreaker,
        timeout: float = 300.0,
        polling_interval: float = 5.0,
        master_purpose: str = None,
        slave_purpose: str = None
    ):
        self.name = name
        self.master_tier = master_tier
        self.slave_tier = slave_tier
        self.master_purpose = master_purpose
        self.slave_purpose = slave_purpose
        self.ports = ports
        self.protocol = protocol
        self.bidirectional = bidirectional
        self.vpc_id = vpc_id
        self.aws_client = aws_client
        self.circuit_breaker = circuit_breaker
        self.timeout = timeout
        self.polling_interval = polling_interval
        
        # Results tracking
        self.master_sgs: List[Dict[str, Any]] = []
        self.slave_sgs: List[Dict[str, Any]] = []
        self.rules_created: List[str] = []
        self.errors: List[str] = []
        self.status = "pending"
    
    async def wait_for_sg(self, tier: str, purpose: str = None, timeout: float = None) -> List[Dict[str, Any]]:
        """
        Poll EC2 for security groups with specific FirewallTier tag and optional Purpose filter.
        
        Args:
            tier: FirewallTier tag value
            purpose: Optional Purpose tag value for granular filtering
            timeout: Override default timeout
        
        Returns:
            List of security group dicts
        
        Raises:
            TimeoutError: If timeout exceeded
        """
        if timeout is None:
            timeout = self.timeout
            
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                sgs = await self.circuit_breaker.call(
                    self.aws_client.find_security_groups_by_tier,
                    self.vpc_id,
                    tier,
                    purpose
                )
                
                if sgs:
                    return sgs
                
                await asyncio.sleep(self.polling_interval)
                
            except Exception as e:
                purpose_info = f" (purpose={purpose})" if purpose else ""
                self.errors.append(f"Error polling for tier '{tier}'{purpose_info}: {str(e)}")
                await asyncio.sleep(self.polling_interval)
        
        purpose_info = f" with purpose '{purpose}'" if purpose else ""
        raise TimeoutError(f"Timeout waiting for security groups with tier '{tier}'{purpose_info}")
    
    async def create_rules(
        self,
        master_sgs: List[Dict[str, Any]],
        slave_sgs: List[Dict[str, Any]]
    ) -> None:
        """
        Create ingress/egress rules between master and slave security groups.
        
        Master → Slave ingress (slave allows traffic from master)
        Master → Slave egress (master allows traffic to slave) [if bidirectional]
        """
        for master_sg in master_sgs:
            for slave_sg in slave_sgs:
                master_id = master_sg['GroupId']
                slave_id = slave_sg['GroupId']
                
                # Determine port range
                if self.protocol == '-1':
                    from_port = -1
                    to_port = -1
                    port_desc = "all"
                else:
                    from_port = min(self.ports)
                    to_port = max(self.ports)
                    port_desc = f"{from_port}-{to_port}" if from_port != to_port else str(from_port)
                
                description = f"{self.name}: {self.master_tier} → {self.slave_tier} ({port_desc}/{self.protocol})"
                
                # 1. Slave SG ingress: Allow traffic FROM master
                try:
                    rule_exists = await self.circuit_breaker.call(
                        self.aws_client.rule_exists,
                        slave_id,
                        'ingress',
                        self.protocol,
                        from_port,
                        to_port,
                        source_group_id=master_id
                    )
                    
                    if not rule_exists:
                        await self.circuit_breaker.call(
                            self.aws_client.create_ingress_rule,
                            slave_id,
                            self.protocol,
                            from_port,
                            to_port,
                            master_id,
                            description
                        )
                        self.rules_created.append(
                            f"✅ {slave_sg['GroupName']} ← {master_sg['GroupName']} (ingress)"
                        )
                    else:
                        self.rules_created.append(
                            f"⏭️  {slave_sg['GroupName']} ← {master_sg['GroupName']} (already exists)"
                        )
                except Exception as e:
                    self.errors.append(
                        f"❌ Failed to create ingress rule {slave_sg['GroupName']} ← {master_sg['GroupName']}: {str(e)}"
                    )
                
                # 2. Master SG egress: Allow traffic TO slave (if bidirectional)
                if self.bidirectional:
                    try:
                        rule_exists = await self.circuit_breaker.call(
                            self.aws_client.rule_exists,
                            master_id,
                            'egress',
                            self.protocol,
                            from_port,
                            to_port,
                            source_group_id=slave_id
                        )
                        
                        if not rule_exists:
                            await self.circuit_breaker.call(
                                self.aws_client.create_egress_rule,
                                master_id,
                                self.protocol,
                                from_port,
                                to_port,
                                slave_id,
                                description
                            )
                            self.rules_created.append(
                                f"✅ {master_sg['GroupName']} → {slave_sg['GroupName']} (egress)"
                            )
                        else:
                            self.rules_created.append(
                                f"⏭️  {master_sg['GroupName']} → {slave_sg['GroupName']} (already exists)"
                            )
                    except Exception as e:
                        self.errors.append(
                            f"❌ Failed to create egress rule {master_sg['GroupName']} → {slave_sg['GroupName']}: {str(e)}"
                        )
    
    async def delete_rules(
        self,
        master_sgs: List[Dict[str, Any]],
        slave_sgs: List[Dict[str, Any]]
    ) -> None:
        """Delete ingress/egress rules between master and slave security groups."""
        for master_sg in master_sgs:
            for slave_sg in slave_sgs:
                master_id = master_sg['GroupId']
                slave_id = slave_sg['GroupId']
                
                # Determine port range
                if self.protocol == '-1':
                    from_port = -1
                    to_port = -1
                else:
                    from_port = min(self.ports)
                    to_port = max(self.ports)
                
                # 1. Delete slave SG ingress rule
                try:
                    await self.circuit_breaker.call(
                        self.aws_client.delete_ingress_rule,
                        slave_id,
                        self.protocol,
                        from_port,
                        to_port,
                        master_id
                    )
                    self.rules_created.append(
                        f"🗑️  Deleted {slave_sg['GroupName']} ← {master_sg['GroupName']} (ingress)"
                    )
                except Exception as e:
                    self.errors.append(
                        f"⚠️  Failed to delete ingress rule {slave_sg['GroupName']} ← {master_sg['GroupName']}: {str(e)}"
                    )
                
                # 2. Delete master SG egress rule (if bidirectional)
                if self.bidirectional:
                    try:
                        await self.circuit_breaker.call(
                            self.aws_client.delete_egress_rule,
                            master_id,
                            self.protocol,
                            from_port,
                            to_port,
                            slave_id
                        )
                        self.rules_created.append(
                            f"🗑️  Deleted {master_sg['GroupName']} → {slave_sg['GroupName']} (egress)"
                        )
                    except Exception as e:
                        self.errors.append(
                            f"⚠️  Failed to delete egress rule {master_sg['GroupName']} → {slave_sg['GroupName']}: {str(e)}"
                        )
    
    async def run(self, mode: str = "apply") -> Dict[str, Any]:
        """
        Execute chain monitoring and rule creation/deletion.
        
        Args:
            mode: 'apply' to create rules, 'destroy' to delete rules
        
        Returns:
            Report dict with status and results
        """
        purpose_info = ""
        if self.master_purpose or self.slave_purpose:
            purpose_info = f" (master_purpose={self.master_purpose or 'any'}, slave_purpose={self.slave_purpose or 'any'})"
        
        print(f"\n🔗 Chain: {self.name}")
        print(f"   Master tier: {self.master_tier}{purpose_info}")
        print(f"   Slave tier: {self.slave_tier}")
        print(f"   Ports: {self.ports}, Protocol: {self.protocol}, Bidirectional: {self.bidirectional}")
        print(f"   Mode: {mode}")
        
        try:
            # Step 1: Wait for security groups to exist
            print(f"   ⏳ Waiting for security groups (timeout: {self.timeout}s)...")
            
            master_sgs, slave_sgs = await asyncio.gather(
                self.wait_for_sg(self.master_tier, self.master_purpose, self.timeout),
                self.wait_for_sg(self.slave_tier, self.slave_purpose, self.timeout)
            )
            
            self.master_sgs = master_sgs
            self.slave_sgs = slave_sgs
            
            print(f"   ✅ Found {len(master_sgs)} master SG(s), {len(slave_sgs)} slave SG(s)")
            
            # Step 2: Create or delete rules
            if mode == "apply":
                print(f"   🔧 Creating rules...")
                await self.create_rules(master_sgs, slave_sgs)
            elif mode == "destroy":
                print(f"   🗑️  Deleting rules...")
                await self.delete_rules(master_sgs, slave_sgs)
            
            # Step 3: Determine status
            if self.errors:
                self.status = "partial_success" if self.rules_created else "failed"
                print(f"   ⚠️  Status: {self.status}")
            else:
                self.status = "success"
                print(f"   ✅ Status: {self.status}")
            
        except TimeoutError as e:
            self.status = "timeout"
            self.errors.append(str(e))
            print(f"   ❌ Timeout: {str(e)}")
        
        except Exception as e:
            self.status = "error"
            self.errors.append(f"Unexpected error: {str(e)}")
            print(f"   ❌ Error: {str(e)}")
        
        return {
            'name': self.name,
            'status': self.status,
            'master_tier': self.master_tier,
            'slave_tier': self.slave_tier,
            'master_security_groups': [sg['GroupId'] for sg in self.master_sgs],
            'slave_security_groups': [sg['GroupId'] for sg in self.slave_sgs],
            'rules_created': self.rules_created,
            'errors': self.errors
        }
