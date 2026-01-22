"""
Unit tests for CircuitBreaker.
Tests the existing implementation in src/circuit_breaker.py
"""

import pytest
import asyncio
import sys
import time
from pathlib import Path

# Add src to Python path
src_path = Path(__file__).parent.parent.parent / "src"
sys.path.insert(0, str(src_path))

from circuit_breaker import CircuitBreaker, CircuitState


class TestCircuitBreakerInitialization:
    """Test circuit breaker initialization."""
    
    def test_default_initialization(self):
        """Test circuit breaker with default parameters."""
        cb = CircuitBreaker()
        
        assert cb.failure_threshold == 5
        assert cb.recovery_timeout == 60.0
        assert cb.success_threshold == 2
        assert cb.failure_count == 0
        assert cb.success_count == 0
        assert cb.last_failure_time is None
        assert cb.state == CircuitState.CLOSED
    
    def test_custom_initialization(self):
        """Test circuit breaker with custom parameters."""
        cb = CircuitBreaker(
            failure_threshold=3,
            recovery_timeout=30.0,
            success_threshold=1
        )
        
        assert cb.failure_threshold == 3
        assert cb.recovery_timeout == 30.0
        assert cb.success_threshold == 1
        assert cb.state == CircuitState.CLOSED


class TestCircuitBreakerStates:
    """Test circuit breaker state transitions."""
    
    @pytest.mark.asyncio
    async def test_closed_state_allows_calls(self):
        """Test that CLOSED state allows function execution."""
        cb = CircuitBreaker()
        
        async def successful_func():
            return "success"
        
        result = await cb.call(successful_func)
        
        assert result == "success"
        assert cb.state == CircuitState.CLOSED
        assert cb.failure_count == 0
    
    @pytest.mark.asyncio
    async def test_failure_increments_counter(self):
        """Test that failures increment the failure counter."""
        cb = CircuitBreaker(failure_threshold=3)
        
        async def failing_func():
            raise ValueError("Simulated failure")
        
        # First failure
        with pytest.raises(ValueError):
            await cb.call(failing_func)
        
        assert cb.failure_count == 1
        assert cb.state == CircuitState.CLOSED
    
    @pytest.mark.asyncio
    async def test_threshold_opens_circuit(self):
        """Test that reaching threshold opens the circuit."""
        cb = CircuitBreaker(failure_threshold=3)
        
        async def failing_func():
            raise ValueError("Simulated failure")
        
        # Trigger 3 failures to reach threshold
        for i in range(3):
            with pytest.raises(ValueError):
                await cb.call(failing_func)
        
        assert cb.failure_count == 3
        assert cb.state == CircuitState.OPEN
        assert cb.last_failure_time is not None
    
    @pytest.mark.asyncio
    async def test_open_circuit_rejects_calls(self):
        """Test that OPEN circuit rejects calls immediately."""
        cb = CircuitBreaker(failure_threshold=2, recovery_timeout=10.0)
        
        async def failing_func():
            raise ValueError("Simulated failure")
        
        # Trigger failures to open circuit
        for i in range(2):
            with pytest.raises(ValueError):
                await cb.call(failing_func)
        
        assert cb.state == CircuitState.OPEN
        
        # Next call should be rejected without executing
        async def should_not_execute():
            pytest.fail("This function should not execute")
        
        with pytest.raises(Exception) as exc_info:
            await cb.call(should_not_execute)
        
        assert "Circuit breaker OPEN" in str(exc_info.value)
    
    @pytest.mark.asyncio
    async def test_half_open_after_timeout(self):
        """Test that circuit transitions to HALF_OPEN after timeout."""
        cb = CircuitBreaker(failure_threshold=2, recovery_timeout=0.1)  # 100ms timeout
        
        async def failing_func():
            raise ValueError("Simulated failure")
        
        # Open the circuit
        for i in range(2):
            with pytest.raises(ValueError):
                await cb.call(failing_func)
        
        assert cb.state == CircuitState.OPEN
        
        # Wait for recovery timeout
        await asyncio.sleep(0.2)
        
        # Next call should attempt execution (HALF_OPEN)
        async def successful_func():
            return "recovered"
        
        result = await cb.call(successful_func)
        
        assert result == "recovered"
        # State should be HALF_OPEN or CLOSED depending on success_threshold
    
    @pytest.mark.asyncio
    async def test_half_open_success_closes_circuit(self):
        """Test that successful calls in HALF_OPEN close the circuit."""
        cb = CircuitBreaker(
            failure_threshold=2,
            recovery_timeout=0.1,
            success_threshold=2
        )
        
        async def failing_func():
            raise ValueError("Failure")
        
        async def successful_func():
            return "success"
        
        # Open circuit
        for i in range(2):
            with pytest.raises(ValueError):
                await cb.call(failing_func)
        
        assert cb.state == CircuitState.OPEN
        
        # Wait for recovery
        await asyncio.sleep(0.2)
        
        # Execute success_threshold successful calls
        await cb.call(successful_func)
        assert cb.success_count == 1
        
        await cb.call(successful_func)
        
        # Should be CLOSED now
        assert cb.state == CircuitState.CLOSED
        assert cb.failure_count == 0
    
    @pytest.mark.asyncio
    async def test_half_open_failure_reopens_circuit(self):
        """Test that failure in HALF_OPEN reopens the circuit."""
        cb = CircuitBreaker(failure_threshold=2, recovery_timeout=0.1)
        
        async def failing_func():
            raise ValueError("Failure")
        
        # Open circuit
        for i in range(2):
            with pytest.raises(ValueError):
                await cb.call(failing_func)
        
        assert cb.state == CircuitState.OPEN
        
        # Wait for recovery
        await asyncio.sleep(0.2)
        
        # Fail in HALF_OPEN
        with pytest.raises(ValueError):
            await cb.call(failing_func)
        
        # Should be OPEN again
        assert cb.state == CircuitState.OPEN


class TestCircuitBreakerWithSyncFunctions:
    """Test circuit breaker with synchronous functions."""
    
    @pytest.mark.asyncio
    async def test_sync_function_success(self):
        """Test that circuit breaker works with sync functions."""
        cb = CircuitBreaker()
        
        def sync_func():
            return "sync_result"
        
        result = await cb.call(sync_func)
        
        assert result == "sync_result"
        assert cb.state == CircuitState.CLOSED
    
    @pytest.mark.asyncio
    async def test_sync_function_failure(self):
        """Test that circuit breaker handles sync function failures."""
        cb = CircuitBreaker(failure_threshold=2)
        
        def sync_failing_func():
            raise RuntimeError("Sync failure")
        
        with pytest.raises(RuntimeError):
            await cb.call(sync_failing_func)
        
        assert cb.failure_count == 1


class TestCircuitBreakerBehavior:
    """Test circuit breaker edge cases and behavior."""
    
    @pytest.mark.asyncio
    async def test_success_resets_failure_count_in_closed(self):
        """Test that success resets failure count in CLOSED state."""
        cb = CircuitBreaker(failure_threshold=5)
        
        async def failing_func():
            raise ValueError("Failure")
        
        async def successful_func():
            return "success"
        
        # Accumulate some failures
        for i in range(3):
            with pytest.raises(ValueError):
                await cb.call(failing_func)
        
        assert cb.failure_count == 3
        
        # Success should reset counter
        await cb.call(successful_func)
        
        assert cb.failure_count == 0
        assert cb.state == CircuitState.CLOSED
    
    @pytest.mark.asyncio
    async def test_last_failure_time_updated(self):
        """Test that last_failure_time is updated on failures."""
        cb = CircuitBreaker()
        
        async def failing_func():
            raise ValueError("Failure")
        
        assert cb.last_failure_time is None
        
        with pytest.raises(ValueError):
            await cb.call(failing_func)
        
        assert cb.last_failure_time is not None
        assert isinstance(cb.last_failure_time, float)
