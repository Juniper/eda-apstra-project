TAG ?= latest

# Get all .py files in the EDA_COLLECTION_ROOT directory
PY_FILES := $(shell find $(EDA_COLLECTION_ROOT) -name *.py)

PY_VERSION := $(shell cat .python-version)

.PHONY: setup eda-decision-environment tower-execution-environment aos_sdk clean clean-pipenv pipenv

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
	pyenv uninstall --force $(PY_VERSION)
	rm -rf $(HOME)/.pyenv/versions/$(PY_VERSION)
	$(PYENV_INSTALL_PREFIX) pyenv install --force $(PY_VERSION)
	pip install pipenv pre-commit
	$(MAKE) pipenv
	pre-commit install

pipenv:
	which pipenv &>/dev/null || pip install pipenv
	pipenv install --dev

eda-decision-environment: pipenv
	pipenv run eda-decision-environment/build_image.sh $(TAG)

tower-execution-environment/aos-sdk:
	mkdir -p tower-execution-environment/aos-sdk

tower-execution-environment/aos-sdk/aos_sdk-0.1.0-py3-none-any.whl: tower-execution-environment/aos-sdk
	# If this fails, download the wheel from juniper.net to the aos-sdk directory...
	(test -r "$@" && touch "$@") || curl -fso "$@" https://s-artifactory.juniper.net:443/artifactory/atom-generic/aos_sdk_5.0.0-RC5/aos_sdk-0.1.0-py3-none-any.whl 2>/dev/null

aos_sdk: tower-execution-environment/aos-sdk/aos_sdk-0.1.0-py3-none-any.whl

tower-execution-environment: pipenv aos_sdk
	pipenv run tower-execution-environment/build_image.sh $(TAG)

# Ignore warnings about localhost from ansible-playbook
export ANSIBLE_LOCALHOST_WARNING=False
export ANSIBLE_INVENTORY_UNPARSED_WARNING=False

clean-pipenv:
	pipenv --rm || true
	PIPENV_VENV_IN_PROJECT= pipenv --rm &>/dev/null || true
	rm -rf .venv
