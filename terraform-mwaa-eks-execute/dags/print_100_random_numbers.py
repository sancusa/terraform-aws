from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from datetime import datetime

with DAG(
    dag_id="kubernetes_pod_random_numbers",
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["eks", "fargate", "logs"],
) as dag:

    print_random_numbers = KubernetesPodOperator(
        task_id="print_100_random_numbers",
        name="random-numbers-pod",
        namespace="default",
        image="python:3.9",
        cmds=["python", "-c"],
        arguments=[
            "import random; [print(random.randint(1, 1000)) for _ in range(100)]"
        ],
        in_cluster=False,
        is_delete_operator_pod=True,
        get_logs=True,
        log_events_on_failure=True,
    )
