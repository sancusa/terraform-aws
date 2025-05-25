from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

def hello_mwaa():
    print("✅ Hello from MWAA! This is a test run.")

with DAG(
    dag_id='test_hello_mwaa',
    schedule_interval=None,  # Only manual trigger
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['test'],
) as dag:
    run_task = PythonOperator(
        task_id='say_hello',
        python_callable=hello_mwaa
    )
