from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from datetime import datetime

with DAG(
    dag_id="kubernetes_pod_debug_random",
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["eks", "fargate", "debug"],
) as dag:

    debug_random = KubernetesPodOperator(
        task_id="debug_eks_and_print_random_numbers",
        name="debug-eks-pod",
        namespace="default",
        image="python:3.9",
        cmds=["python", "-c"],
        arguments=[
            """
import socket, os, random
print("✅ Pod Info:")
print("Hostname:", socket.gethostname())
print("Pod IP:", socket.gethostbyname(socket.gethostname()))
print("Namespace:", os.getenv("NAMESPACE", "default"))
print("Node Name:", os.getenv("NODE_NAME", "unknown"))
print("\\n📊 Generating 2,000 random numbers:")
for _ in range(2000): print(random.randint(1, 10000))
"""
        ],
        in_cluster=False,
        kubernetes_conn_id="k8s_default",  # ✅ this must exist
        is_delete_operator_pod=True,
        get_logs=True,
        log_events_on_failure=True,
    )
