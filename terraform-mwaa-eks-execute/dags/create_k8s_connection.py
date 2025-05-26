from airflow import DAG
from airflow.models import Connection
from airflow.operators.python import PythonOperator
from airflow.utils.dates import days_ago
from airflow.utils.session import provide_session
from sqlalchemy.orm.session import Session


@provide_session
def create_k8s_conn(session: Session = None):
    conn_id = "k8s_default"
    # Delete existing connection if it exists
    existing = session.query(Connection).filter(Connection.conn_id == conn_id).first()
    if existing:
        session.delete(existing)
        session.commit()

    # Create a Kubernetes connection using IAM
    conn = Connection(
        conn_id=conn_id,
        conn_type="kubernetes",
        extra="""
        {
            "extra__kubernetes__in_cluster": false,
            "extra__kubernetes__namespace": "default",
            "extra__kubernetes__use_iam_backend": true,
            "extra__kubernetes__verify_ssl": true
        }
        """
    )
    session.add(conn)
    session.commit()


with DAG(
    dag_id="create_k8s_connection",
    schedule_interval=None,
    start_date=days_ago(1),
    catchup=False,
    tags=["config", "setup"],
) as dag:

    create_conn = PythonOperator(
        task_id="upsert_kubernetes_connection",
        python_callable=create_k8s_conn,
    )
