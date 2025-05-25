import random
from datetime import datetime
import time

for i in range(200):
    print(f"{datetime.utcnow()} | Iteration {i+1}: Random number = {random.randint(1, 10000)}")
    time.sleep(0.1)
