from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import random
import time
import os

# Default DAG args
default_args = {
    'owner': 'airflow',
    'start_date': datetime(2024, 1, 1),
    'retries': 0,
}

dag = DAG(
    dag_id='test_random_numbers_dag',
    default_args=default_args,
    schedule_interval=None,  # Only runs when triggered manually
    catchup=False,
    description='Test DAG that prints system info and random numbers with timestamps'
)

def print_sysinfo():
    import platform
    print("System:", platform.platform())
    print("Python Version:", platform.python_version())
    print("Environment Variables:")
    for k, v in os.environ.items():
        print(f"{k}={v}")

def print_random_numbers():
    for i in range(200):
        ts = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')
        print(f"{__file__} | Iteration {i+1} | Timestamp: {ts} | Random number: {random.randint(1, 10000)}")
        time.sleep(0.05)

task_sysinfo = PythonOperator(
    task_id='print_system_info',
    python_callable=print_sysinfo,
    dag=dag
)

task_random_numbers = PythonOperator(
    task_id='print_random_numbers',
    python_callable=print_random_numbers,
    dag=dag
)

task_sysinfo >> task_random_numbers
