import pytest
import yaml
from kubernetes import client, config
from kubernetes.stream import stream as k8s_stream 
from kubernetes.client.rest import ApiException
import subprocess
import time
import json

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

def check_deployment_status(deployment_name, namespace):
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

def get_pod_ext0_ip(deployment_name, namespace):
    """
    Get the IP address of the ext3 interface of a pod in the specified deployment.

    :param deployment_name: Name of the deployment
    :param namespace: Namespace where the deployment resides
    :return: IP address of the ext3 interface
    """
    try:
        # Get the label selector for the deployment
        deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
        label_selector = ",".join([f"{k}={v}" for k, v in deployment.spec.selector.match_labels.items()])

        # List pods matching the label selector
        pods = v1.list_namespaced_pod(namespace, label_selector=label_selector)
        if not pods.items:
            pytest.fail(f"No pods found for deployment '{deployment_name}' in namespace '{namespace}'")

        # Retrieve the ext3 IP from the pod annotations or status
        pod = pods.items[0]  # Assuming you want the first pod
        network_info = pod.metadata.annotations.get("k8s.v1.cni.cncf.io/network-status", "")
        if network_info:
            network_info_str = json.loads(network_info)
            for network in network_info_str:
                if network.get("interface") == "ext0":
                    return network.get("ips", [None])[0]
        pytest.fail(f"ext3 interface IP not found for pod '{pod.metadata.name}'")
    except ApiException as e:
        pytest.fail(f"Failed to get pod IP: {e}")

def get_kubevirtvm_ip_from_user_data(kubevirtvm_name, namespace):
    """
    Get the IP address from the addresses field in the userData of the cloudInitConfigDrive volume.

    :param kubevirtvm_name: Name of the KubeVirt VM
    :param namespace: Namespace where the KubeVirt VM resides
    :return: IP address from the addresses field
    """
    try:
        # Custom resource API group and version
        group = "kubevirt.io"
        version = "v1"
        plural = "virtualmachines"

        # Fetch the KubeVirt VM custom resource
        kubevirtvm = client.CustomObjectsApi().get_namespaced_custom_object(
            group=group, version=version, namespace=namespace, plural=plural, name=kubevirtvm_name
        )
        if not kubevirtvm:
            pytest.fail(f"KubeVirt VM '{kubevirtvm_name}' not found in namespace '{namespace}'")

        # Extract the userData from the cloudInitConfigDrive volume
        volumes = kubevirtvm.get("spec", {}).get("template", {}).get("spec", {}).get("volumes", [])
        if not volumes:
            pytest.fail(f"No volumes found for KubeVirt VM '{kubevirtvm_name}'")
        for volume in volumes:
            if "cloudInitConfigDrive" in volume:
                user_data = volume["cloudInitConfigDrive"].get("userData", "")
                if user_data:
                    cloud_config = yaml.safe_load(user_data)
                    network_config = cloud_config.get("write_files", [])[0].get("content", "")
                    network_data = yaml.safe_load(network_config)
                    enp7s0_config = network_data.get("network", {}).get("ethernets", {}).get("enp7s0", {})
                    addresses = enp7s0_config.get("addresses", [])
                    if addresses:
                        # Extract the IP address (remove the CIDR suffix)
                        return addresses[0].split('/')[0]

        pytest.fail(f"IP address not found in userData of KubeVirt VM '{kubevirtvm_name}'")
    except ApiException as e:
        pytest.fail(f"Failed to get IP from userData for KubeVirt VM '{kubevirtvm_name}': {e}")

def test_network_connectivity(deploy_helm_chart):
    # Verify network connectivity from Vnet1 IP to Vnet2 IP
    kubevirtvm_name = helm_values['workloads']['kubevirtvm']['name']
    deployment_name = helm_values['workloads']['deployment']['name']
    namespace = "apstra-rhocp-demo-helm"
    check_deployment_status(deployment_name, namespace)
    # Get Vnet1 and Vnet2 IPs
    vnet1_ip = get_pod_ext0_ip(deployment_name, namespace)
    if not vnet1_ip:
        pytest.fail(f"Network connectivity test failed: {e}")
        pytest.fail(f"Failed to get ext3 IP for deployment '{deployment_name}': {e}")
    vnet2_ip = get_kubevirtvm_ip_from_user_data(kubevirtvm_name, namespace)
    if not vnet2_ip:
        pytest.fail(f"Network connectivity test failed: {e}")            
        pytest.fail(f"Failed to get ext3 IP for deployment '{kubevirtvm_name}': {e}")
    #vnet2_ip = helm_values['workloads']['kubevirtvm']['sriovnet']['rangeStart']

    # Get Vnet1 pod name
    deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
    label_selector = ",".join([f"{k}={v}" for k, v in deployment.spec.selector.match_labels.items()])
    pods = v1.list_namespaced_pod(namespace, label_selector=label_selector)
    if not pods.items:
        pytest.fail(f"No pods found for deployment '{deployment_name}' in namespace '{namespace}'")
    vnet1_pod_name = pods.items[0].metadata.name

    # Execute ping command from Vnet1 pod to Vnet2 IP
    ping_command = ["ping", "-c", "3", vnet2_ip]
    try:
        resp = k8s_stream(v1.connect_get_namespaced_pod_exec,
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
