import pytest
import yaml
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import subprocess

# Load Kubernetes configuration
config.load_kube_config()

# Define Kubernetes clients
v1 = client.CoreV1Api()
apps_v1 = client.AppsV1Api()

# Load Helm values file
with open("playbooks/helm-charts/juniper-eda-validator/values.yaml", 'r') as stream:
    helm_values = yaml.safe_load(stream)

@pytest.fixture(scope="module")
def deploy_helm_chart():
    # Deploy the Helm chart
    release_name = "juniper-eda-validator"
    chart_path = "playbooks/helm-charts/juniper-eda-validator"
    namespace = "default"

    # Install Helm chart
    install_cmd = [
        "helm", "install", release_name, chart_path,
        "--namespace", namespace,
        "--values", "playbooks/helm-charts/juniper-eda-validator/values.yaml"
    ]
    subprocess.run(install_cmd, check=True)

    yield

    # Teardown: Uninstall Helm chart
    uninstall_cmd = ["helm", "uninstall", release_name, "--namespace", namespace]
    # subprocess.run(uninstall_cmd, check=True)

def test_deployment_exists(deploy_helm_chart):
    # Verify deployment exists
    deployment_name = helm_values['workloads']['deployment']['name']
    namespace = "apstra-rhocp-demo-helm"
    max_retries = 10 # Maximum number of retries
    wait_seconds = 10  # Wait time between retries
    try:
        for i in range(max_retries):
            deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
            available_replicas = deployment.status.available_replicas
            desired_replicas = deployment.spec.replicas

            if available_replicas == desired_replicas:
                assert deployment.metadata.name == deployment_name
                break  # Exit the loop once the deployment is ready
            else:
                time.sleep(wait_seconds)  # Wait before retrying
        else:
            pytest.fail(f"Deployment test failed: Deployment '{deployment_name}' did not become ready in time.")
    except ApiException as e:
        pytest.fail(f"Deployment test failed: {e}")

def test_kubevirtvm_exists(deploy_helm_chart):
    # Verify kubevirtvm exists (assuming it's a custom resource)
    kubevirtvm_name = helm_values['workloads']['kubevirtvm']['name']
    namespace = "apstra-rhocp-demo-helm"

    # Custom resource API group and version
    group = "kubevirt.io"
    version = "v1alpha3"
    plural = "virtualmachines"

    try:
        kubevirtvm = client.CustomObjectsApi().get_namespaced_custom_object(
            group=group, version=version, namespace=namespace, plural=plural, name=kubevirtvm_name)
        assert kubevirtvm['metadata']['name'] == kubevirtvm_name
    except ApiException as e:
        pytest.fail(f"KubeVirt VM test failed: {e}")

def test_network_connectivity(deploy_helm_chart):
    # Verify network connectivity from Vnet1 IP to Vnet2 IP
    deployment_name = helm_values['workloads']['deployment']['name']
    namespace = "apstra-rhocp-demo-helm"
    vnet1_pod_label = f"app={deployment_name}"
    vnet2_ip = helm_values['workloads']['kubevirtvm']['sriovnet']['rangeStart']

    # Get Vnet1 pod name
    pods = v1.list_namespaced_pod(namespace)
    if not pods.items:
        pytest.fail("No pods found for Vnet1 deployment")
    vnet1_pod_name = pods.items[0].metadata.name

    # Execute ping command from Vnet1 pod to Vnet2 IP
    ping_command = ["ping", "-c", "3", vnet2_ip]
    try:
        resp = v1.connect_get_namespaced_pod_exec(
            vnet1_pod_name, namespace,
            command=ping_command,
            stderr=True, stdin=False,
            stdout=True, tty=False
        )
        assert "3 packets transmitted, 3 received" in resp
    except ApiException as e:
        pytest.fail(f"Network connectivity test failed: {e}")

if __name__ == "__main__":
    pytest.main()
