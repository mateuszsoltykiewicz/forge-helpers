"""Circuit breaker pattern implementation for AWS API calls."""

import asyncio
import time
from enum import Enum
from typing import Callable, Any, TypeVar

T = TypeVar('T')


class CircuitState(Enum):
    """Circuit breaker states."""
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, reject calls
    HALF_OPEN = "half_open"  # Testing recovery


class CircuitBreaker:
    """
    Circuit breaker to prevent cascading failures.
    
    - CLOSED: Normal operation
    - OPEN: After failure_threshold failures, reject calls for recovery_timeout seconds
    - HALF_OPEN: After recovery timeout, allow success_threshold calls to test recovery
    """
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 60.0,
        success_threshold: int = 2
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.success_threshold = success_threshold
        
        self.failure_count = 0
        self.success_count = 0
        self.last_failure_time = None
        self.state = CircuitState.CLOSED
    
    async def call(self, func: Callable[..., Any], *args, **kwargs) -> Any:
        """Execute function with circuit breaker protection."""
        
        # Check if circuit should transition from OPEN to HALF_OPEN
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time >= self.recovery_timeout:
                print(f"   Circuit breaker: OPEN → HALF_OPEN (testing recovery)")
                self.state = CircuitState.HALF_OPEN
                self.success_count = 0
            else:
                raise Exception(
                    f"Circuit breaker OPEN. "
                    f"Retry after {self.recovery_timeout - (time.time() - self.last_failure_time):.1f}s"
                )
        
        try:
            # Execute the function
            if asyncio.iscoroutinefunction(func):
                result = await func(*args, **kwargs)
            else:
                result = func(*args, **kwargs)
            
            # Success handling
            if self.state == CircuitState.HALF_OPEN:
                self.success_count += 1
                if self.success_count >= self.success_threshold:
                    print(f"   Circuit breaker: HALF_OPEN → CLOSED (recovery successful)")
                    self.state = CircuitState.CLOSED
                    self.failure_count = 0
            elif self.state == CircuitState.CLOSED:
                # Reset failure count on success
                self.failure_count = 0
            
            return result
            
        except Exception as e:
            # Failure handling
            self.failure_count += 1
            self.last_failure_time = time.time()
            
            if self.state == CircuitState.HALF_OPEN:
                print(f"   Circuit breaker: HALF_OPEN → OPEN (recovery failed)")
                self.state = CircuitState.OPEN
            elif self.failure_count >= self.failure_threshold:
                print(f"   Circuit breaker: CLOSED → OPEN (threshold reached: {self.failure_count})")
                self.state = CircuitState.OPEN
            
            raise e
