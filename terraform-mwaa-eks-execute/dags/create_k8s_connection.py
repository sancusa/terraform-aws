from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.models import Connection
from airflow.operators.python import PythonOperator
from airflow.utils.session import provide_session
from sqlalchemy.orm.session import Session


def create_k8s_conn(**kwargs):
    conn_id = "k8s_default"
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
        """,
    )

    @provide_session
    def upsert_connection(session: Session = None):
        existing = session.query(Connection).filter(Connection.conn_id == conn.conn_id).first()
        if existing:
            session.delete(existing)
        session.add(conn)
        session.commit()

    upsert_connection()

with DAG(
    dag_id="create_k8s_connection",
    schedule_interval=None,
    start_date=days_ago(1),
    catchup=False,
) as dag:

    create_connection = PythonOperator(
        task_id="create_k8s_conn_task",
        python_callable=create_k8s_conn,
    )
