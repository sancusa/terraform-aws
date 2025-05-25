from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from datetime import datetime

with DAG(
    dag_id="run_random_number_pod",
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
) as dag:

    run_task = KubernetesPodOperator(
        task_id="print-random-numbers",
        name="print-random-numbers",
        namespace="airflow",
        image="613505198708.dkr.ecr.us-east-1.amazonaws.com/ecr-terraform-mwaa-amazonq",
        cmds=["python"],
        arguments=["/app/print_random.py"],
        service_account_name="airflow-irsa",
        get_logs=True,
        is_delete_operator_pod=True
    )
