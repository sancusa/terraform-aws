import random
import time

for i in range(1, 2001):
    print(f"{__file__} | Iteration {i}: Random number generated: {random.randint(1, 10000)}")
    time.sleep(0.1)  # to slow down the output a bit