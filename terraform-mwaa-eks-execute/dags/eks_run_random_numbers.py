from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from datetime import datetime

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
}

kube_config_path = '/usr/local/airflow/dags/kube_config.yaml'

with DAG(
    dag_id='mwaa_run_on_eks',
    default_args=default_args,
    description='Run Python task in EKS via KubernetesPodOperator',
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['eks', 'mwaa'],
) as dag:

    run_random_numbers = KubernetesPodOperator(
        task_id='run-random-numbers',
        name='print-random-job',
        namespace='airflow',
        image='613505198708.dkr.ecr.us-east-1.amazonaws.com/ecr-terraform-mwaa-amazonq',
        cmds=['python'],
        arguments=['/app/print_random.py'],
        service_account_name='airflow-irsa',
        get_logs=True,
        config_file=kube_config_path,
        in_cluster=False,
        is_delete_operator_pod=True,
    )
