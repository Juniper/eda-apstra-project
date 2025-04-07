TAG ?= latest

PY_VERSION := $(shell cat .python-version)

.PHONY: setup clean-pipenv pipenv

# OS-specific settings
OS := $(shell uname -s)
ifeq ($(OS),Darwin)
PYENV_INSTALL_PREFIX := PYTHON_CONFIGURE_OPTS=--enable-framework
else
# Unix
endif

# By default use .venv in the current directory
export PIPENV_VENV_IN_PROJECT=1

setup: clean-pipenv
	pyenv uninstall --force $(PY_VERSION) 2>/dev/null
	rm -rf $(HOME)/.pyenv/versions/$(PY_VERSION)
	$(PYENV_INSTALL_PREFIX) pyenv install --force $(PY_VERSION)
	pip install pipenv pre-commit
	$(MAKE) pipenv
	pre-commit install

pipenv:
	which pipenv &>/dev/null || pip install pipenv
	pipenv install --dev
test: 
	pipenv run pip install pytest kubernetes pyyaml
	pipenv run pytest feature_tests/test_deploy_helm_chart.py
# Ignore warnings about localhost from ansible-playbook
export ANSIBLE_LOCALHOST_WARNING=False
export ANSIBLE_INVENTORY_UNPARSED_WARNING=False

clean-pipenv:
	pipenv --rm || true
	PIPENV_VENV_IN_PROJECT= pipenv --rm &>/dev/null || true
	rm -rf .venv
