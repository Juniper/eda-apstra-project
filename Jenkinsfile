pipeline {
    agent {
        label 'apstra-ansible'
    }
    environment {
        PATH             = credentials('AGENT_PATH')
        APSTRA_API_URL   = credentials('APSTRA_API_URL')
        APSTRA_VERIFY_CERTIFICATES = 0
    }
    parameters {
        string(name: 'apstraeeimage', defaultValue: '', description: 'apstra ee image')
        string(name: 'apstradeimage', defaultValue: '', description: 'apstra de image')
    }

    stages {
        stage('Configure') {
            steps {
                script {
                    run_playbook()
                }
            }
        }

        stage('Feature Test') {
            steps {
                sh 'make test'
            }
        }
    }
}

def run_playbook() {
    def eeworkspace = "/home/contrail/workspace/eda-apstra/build"
    def filedir     = "${eeworkspace}/apstra-aap-configure/files"

    withCredentials([
        string(credentialsId: 'AAP_CONTR',   variable: 'aap_pass'),
        string(credentialsId: 'EDA_CONTR',   variable: 'eda_pass'),
        string(credentialsId: 'APSTRA_PASS', variable: 'apstra_pass')
    ]) {
        def env_vars = ""

        if (params.apstraeeimage) {
            println "Checking ee"
            env_vars += "execution_environment_image_url=${params.apstraeeimage}"
        }

        if (params.apstradeimage) {
            env_vars += " decision_environment_image_url=${params.apstradeimage}"
        }

        env_vars += " automation_controller_password=${aap_pass}"
        env_vars += " eda_controller_password=${eda_pass}"
        env_vars += " apstra_password=${apstra_pass}"
        env_vars += " apstra_username=ci-user"
        env_vars = "\"${env_vars}\""

        dir(filedir) {
            sh '''#!/bin/bash
                kubectl get secret aap -n aap -o json \
                    | jq '.data.token' \
                    | xargs \
                    | base64 --decode > openshift-sa.token
            '''
        }

        dir(eeworkspace) {
            sh "ansible-playbook -e ${env_vars} apstra-eda-build.yaml"
        }
    }
}
