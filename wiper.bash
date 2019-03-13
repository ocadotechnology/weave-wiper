#!/bin/bash

HTTP_ADDR="${WEAVE_HTTP_ADDR:-127.0.0.1:6784}"
CONTAINER_NAME="${WEAVE_CONTAINER_NAME:-weave}"
SOCKET_VOLUME_PATH="${SOCKET_VOLUME_PATH:-"/host/run/docker.sock"}"
ENGINE_API="${ENGINE_API:-"1.24"}"
CONTAINERS_ENDPOINT="${CONTAINERS_ENDPOINT:-"/containers/json"}"

log_this(){
  jq -cn --arg datetime "$(date -Iseconds)" --arg level "$1" --arg message "$2" '{"@timestamp": $datetime, "@version": 1, "level": $level, "message": $message}' || exit $?
}

http_call() {
  local addr="$1"
  local http_verb="$2"
  local url="$3"
  shift 3
  local CURL_TMPOUT="/tmp/weave_curl_out_$$"
  local HTTP_CODE=$(curl -o ${CURL_TMPOUT} -w '%{http_code}' --connect-timeout 3 -s -S -X ${http_verb} "${@}" http://${addr}${url}) || return ${?}
  case "${HTTP_CODE}" in
    2??) # 2xx -> not an error; output response on stdout
      [[ -f "${CURL_TMPOUT}" ]]
      retval=0
      ;;
    404) # treat as error but swallow response
      retval=4
      ;;
    *) # anything else is an error; output response on stderr
      [[ -f "${CURL_TMPOUT}" ]] && log_this "ERROR" $(jq -Rs . <"${CURL_TMPOUT}")
      retval=1
  esac
  return ${retval}
}

call_weave() {
  local TMPERR="/tmp/call_weave_err_$$"
  local exitcode=0
  http_call "${HTTP_ADDR}" "${@}" 2>"${TMPERR}" || exitcode=${?}
  if [[ ${exitcode} -ne 0 ]] ; then
    log_this "ERROR" $(jq -Rsr . <"${TMPERR}")
    exit ${exitcode}
  fi
  rm -f "${TMPERR}"
}

can_see_socket() {
  if [[ ! -S "${SOCKET_VOLUME_PATH}" ]]; then
    log_this "ERROR" "ERROR: Docker socket file not visible"
    exit 1
  else
    log_this "INFO" "INFO: Docker socket mounted"
  fi
}

T_get_weave_ids() {
  local result=0
  result=$(cat test/curl-weave | get_weave_ids)
  [[ "${result}" = "$(cat test/weave-ids)" ]]
}

get_weave_ids() {
  # The special container with ID "weave:expose" shouldn't be in the list 
  jq -r '.owned[]?.containerid' | sort | sed '/expose/d'
}

get_weave_containers() {
  # Gets list of containers from weave.
  call_weave GET /ip
  cat /tmp/weave_curl_out_$$ | get_weave_ids
}

T_get_docker_ids() {
  local result=0
  result=$(cat test/containers-json | get_docker_ids)
  [[ "${result}" = "$(cat test/docker-ids)" ]]

}

get_docker_ids() {
  jq -r '.[].Id' | sort  
}

get_docker_container_ids() {
  curl -s --unix-socket ${SOCKET_VOLUME_PATH} "http://${ENGINE_API}${CONTAINERS_ENDPOINT}" | get_docker_ids
}

T_ids_wrong_files_validation_containers-json() {
  local result=0
  ids_file_validation test/containers-json || result=${?}
  [[ ${result} != 0 ]]
}

T_ids_wrong_files_validation_curl-weave() {
  local result=0
  ids_file_validation test/curl-weave || result=${?}
  [[ ${result} != 0 ]]
}

T_ids_wrong_files_validation_weave-with-expose() {
  local result=0
  ids_file_validation test/weave-with-expose || result=${?}
  [[ ${result} != 0 ]]
}

T_ids_wrong_files_validation_emptyfile() {
  local result=0
  ids_file_validation test/emptyfile || result=${?}
  [[ ${result} != 0 ]]
}

T_ids_file_validation() {
  local result=0
  ids_file_validation test/docker-ids || result=${?}
  [[ ${result} != 0 ]]
}

ids_file_validation() {
  local file_to_validate="${1}"
  if [[ ! -f ${file_to_validate} ]]; then
    log_this "ERROR" "ERROR: container list file ${file_to_validate} not found"
    return 1
  fi
  if [[ ! -s ${file_to_validate} ]]; then
    log_this "ERROR" "ERROR: container list file ${file_to_validate} is empty!"
    return 1
  fi
  for id in $(cat ${file_to_validate}); do
    if [[ ! "${id}" =~ ^[0-9a-f]*\n$ ]]; then
      log_this "ERROR" "ERROR: Wrong container id in docker ids file: ${id}"
      return 1
    fi
  done;
  return 0
}

remove_ids() {
  local counter=0
  local weave_ids_file="${1}"
  local docker_ids_file="${2}"
  for id in $(cat ${weave_ids_file}); do 
    if ! grep -Fxq ${id} ${docker_ids_file}; then
      call_weave DELETE /ip/${id} && log_this "INFO" "INFO: container ${id} is not running. Its address has been wIPed";
      counter=$(expr ${counter} + 1);
    fi;
  done;
  log_this "INFO" "INFO: ${counter} addresses wIPed"
}

loop() {
  readonly loop_period="3600"

  while true; do
    get_weave_containers > /tmp/weave-ids && ids_file_validation /tmp/weave-ids
    get_docker_container_ids > /tmp/docker-ids && ids_file_validation /tmp/docker-ids
    remove_ids /tmp/weave-ids /tmp/docker-ids
    sleep ${loop_period}
  done
}

main() {
  set -e
  log_this "INFO" "Starting weave-wiper"
  can_see_socket
  loop
}

[[ "${0}" == "${BASH_SOURCE}" ]] && main "${@}"
