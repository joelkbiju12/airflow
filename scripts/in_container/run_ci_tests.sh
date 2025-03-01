#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
# shellcheck source=scripts/in_container/_in_container_script_init.sh
. "$( dirname "${BASH_SOURCE[0]}" )/_in_container_script_init.sh"

echo
echo "Starting the tests with those pytest arguments:" "${@}"
echo
set +e

# We have to tweak coverage for Python 3.12 because of the issue with coverage that takes too long, despite
# Using experimental support for Python 3.12 PEP 669. The coverage.py is not yet fully compatible with the
# full scope of PEP-669. That will be fully done when https://github.com/nedbat/coveragepy/issues/1746 is
# resolve for now we are disabling coverage for Python 3.12, but possibly it is enough for now.
PYTHON_3_12_OR_ABOVE=$(python -c "import sys; print(sys.version_info >= (3,12))")

if [[ ${PYTHON_3_12_OR_ABOVE} == "True" ]]; then
    echo
    echo "${COLOR_BLUE}Enabling experimental PEP-669 support in coverage.py for Python 3.12 and above.${COLOR_RESET}"
    echo
    export COVERAGE_CORE=sysmon
fi

pytest "${@}"
RES=$?

if [[ ${RES} == "139" ]]; then
    echo "${COLOR_YELLOW}Sometimes Pytest fails at exiting with segfault, but all tests actually passed${COLOR_RESET}"
    echo "${COLOR_YELLOW}We should ignore such case. Checking if junitxml file ${RESULT_LOG_FILE} is there with 0 errors and failures${COLOR_RESET}"
    if [[ -f ${RESULT_LOG_FILE} ]]; then
        python "${AIRFLOW_SOURCES}/scripts/in_container/check_junitxml_result.py" "${RESULT_LOG_FILE}"
        RES=$?
    else
        echo "${COLOR_YELLOW}JunitXML file ${RESULT_LOG_FILE} does not exist. Proceeding with failure as we cannot check if there were no failures.${COLOR_RESET}"
    fi
fi

set +x
if [[ "${RES}" == "0" && ( ${CI:="false"} == "true" || ${CI} == "True" ) ]]; then
    echo "All tests successful"
fi

MAIN_GITHUB_REPOSITORY="apache/airflow"

if [[ ${TEST_TYPE:=} == "Quarantined" ]]; then
    if [[ ${GITHUB_REPOSITORY=} == "${MAIN_GITHUB_REPOSITORY}" ]]; then
        if [[ ${RES} == "1" || ${RES} == "0" ]]; then
            echo
            echo "Pytest exited with ${RES} result. Updating Quarantine Issue!"
            echo
            "${IN_CONTAINER_DIR}/update_quarantined_test_status.py" "${RESULT_LOG_FILE}"
        else
            echo
            echo "Pytest exited with ${RES} result. NOT Updating Quarantine Issue!"
            echo
        fi
    fi
fi

if [[ ${CI:="false"} == "true" || ${CI} == "True" ]]; then
    if [[ ${RES} != "0" ]]; then
        echo
        echo "Dumping logs on error"
        echo
        dump_airflow_logs
    fi
fi

exit "${RES}"
