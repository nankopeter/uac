#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2001,SC2006

###############################################################################
# Collector that runs commands.
# Globals:
#   GZIP_TOOL_AVAILABLE
#   TEMP_DATA_DIR
# Requires:
#   log_message
# Arguments:
#   $1: loop command (optional)
#   $2: command
#   $3: root output directory
#   $4: output directory (optional)
#   $5: output file
#   $6: stderr output file (optional)
#   $7: compress output file (optional) (default: false)
# Outputs:
#   Write command output to stdout.
#   Write command errors to stderr.
# Exit Status:
#   Exit with status 0 on success.
#   Exit with status greater than 0 if errors occur.
###############################################################################
command_collector()
{
  cc_loop_command="${1:-}"
  cc_command="${2:-}"
  cc_root_output_directory="${3:-}"
  cc_output_directory="${4:-}"
  cc_output_file="${5:-}"
  cc_stderr_output_file="${6:-}"
  cc_compress_output_file="${7:-false}"
  
  # return if command is empty
  if [ -z "${cc_command}" ]; then
    printf %b "command_collector: missing required argument: 'command'\n" >&2
    return 22
  fi

  # return if root output directory is empty
  if [ -z "${cc_root_output_directory}" ]; then
    printf %b "command_collector: missing required argument: \
'root_output_directory'\n" >&2
    return 22
  fi

  # return if output file is empty
  if [ -z "${cc_output_file}" ]; then
    printf %b "command_collector: missing required argument: 'output_file'\n" >&2
    return 22
  fi

  # loop command
  if [ -n "${cc_loop_command}" ]; then

    # create output directory if it does not exist
    if [ ! -d  "${TEMP_DATA_DIR}/${cc_root_output_directory}" ]; then
      mkdir -p "${TEMP_DATA_DIR}/${cc_root_output_directory}" >/dev/null
    fi

    log_message COMMAND "${cc_loop_command}"
    eval "${cc_loop_command}" \
      >"${TEMP_DATA_DIR}/.loop_command.tmp" \
      2>>"${TEMP_DATA_DIR}/${cc_root_output_directory}/loop_command.stderr"
    
    if [ ! -s "${TEMP_DATA_DIR}/.loop_command.tmp" ]; then
      printf %b "command_collector: loop command returned zero lines: \
${cc_loop_command}\n" >&2
      return 61
    fi

    # shellcheck disable=SC2162
    sort -u <"${TEMP_DATA_DIR}/.loop_command.tmp" \
      | while read cc_line || [ -n "${cc_line}" ]; do

          # replace %line% by cc_line value
          cc_new_command=`echo "${cc_command}" \
            | sed -e "s:%line%:${cc_line}:g"`
          
          # replace %line% by cc_line value
          cc_new_output_directory=`echo "${cc_output_directory}" \
            | sed -e "s:%line%:${cc_line}:g"`
          # sanitize output directory
          cc_new_output_directory=`sanitize_path \
            "${cc_root_output_directory}/${cc_new_output_directory}"`
          
          # replace %line% by cc_line value
          cc_new_output_file=`echo "${cc_output_file}" \
            | sed -e "s:%line%:${cc_line}:g"`
          # sanitize output file
          cc_new_output_file=`sanitize_filename \
            "${cc_new_output_file}"`

          if [ -n "${cc_stderr_output_file}" ]; then
            # replace %line% by cc_line value
            cc_new_stderr_output_file=`echo "${cc_stderr_output_file}" \
              | sed -e "s:%line%:${cc_line}:g"`
            # sanitize stderr output file
            cc_new_stderr_output_file=`sanitize_filename \
              "${cc_new_stderr_output_file}"`
          else
            cc_new_stderr_output_file="${cc_new_output_file}.stderr"
          fi        

          # create output directory if it does not exist
          if [ ! -d  "${TEMP_DATA_DIR}/${cc_new_output_directory}" ]; then
            mkdir -p "${TEMP_DATA_DIR}/${cc_new_output_directory}" >/dev/null
          fi

          if echo "${cc_new_command}" | grep -q -E "%output_file%"; then
            # replace %output_file% by ${cc_output_file} in command
            cc_new_command=`echo "${cc_new_command}" \
              | sed -e "s:%output_file%:${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_output_file}:g"`
            # run command and append output to existing file
            log_message COMMAND "${cc_new_command}"
            eval "${cc_new_command}" \
              >>"${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_stderr_output_file}" \
              2>>"${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_stderr_output_file}"
            # remove output file if it is empty
            if [ ! -s "${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_output_file}" ]; then
              rm -f "${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_output_file}" \
                >/dev/null
            fi
          else
            if "${cc_compress_output_file}" && ${GZIP_TOOL_AVAILABLE}; then
              # run command and append output to compressed file
              log_message COMMAND "${cc_new_command} | gzip - | cat -"
              eval "${cc_new_command} | gzip - | cat -" \
                >>"${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_output_file}.gz" \
                2>>"${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_stderr_output_file}"
            else
              # run command and append output to existing file
              log_message COMMAND "${cc_new_command}"
              eval "${cc_new_command}" \
                >>"${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_output_file}" \
                2>>"${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_stderr_output_file}"
              # remove output file if it is empty
              if [ ! -s "${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_output_file}" ]; then
                rm -f "${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_output_file}" \
                  >/dev/null
              fi
            fi
          fi

          # remove stderr output file if it is empty
          if [ ! -s "${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_stderr_output_file}" ]; then
            rm -f "${TEMP_DATA_DIR}/${cc_new_output_directory}/${cc_new_stderr_output_file}" \
              >/dev/null
          fi

        done

    # remove loop_command.stderr file if it is empty
    if [ ! -s "${TEMP_DATA_DIR}/${cc_root_output_directory}/loop_command.stderr" ]; then
      rm -f "${TEMP_DATA_DIR}/${cc_root_output_directory}/loop_command.stderr"  \
        >/dev/null
    fi
 
  else

    # sanitize output file name
    cc_output_file=`sanitize_filename "${cc_output_file}"`
    
    if [ -n "${cc_stderr_output_file}" ]; then
      # sanitize stderr output file name
      cc_stderr_output_file=`sanitize_filename "${cc_stderr_output_file}"`
    else
      cc_stderr_output_file="${cc_output_file}.stderr"
    fi

    # sanitize output directory
    cc_output_directory=`sanitize_path \
      "${cc_root_output_directory}/${cc_output_directory}"`

    # create output directory if it does not exist
    if [ ! -d  "${TEMP_DATA_DIR}/${cc_output_directory}" ]; then
      mkdir -p "${TEMP_DATA_DIR}/${cc_output_directory}" >/dev/null
    fi

    if echo "${cc_command}" | grep -q -E "%output_file%"; then
      # replace %output_file% by ${cc_output_file} in command
      cc_command=`echo "${cc_command}" \
        | sed -e "s:%output_file%:${TEMP_DATA_DIR}/${cc_output_directory}/${cc_output_file}:g"`
      # run command and append output to existing file
      log_message COMMAND "${cc_command}"
      eval "${cc_command}" \
        >>"${TEMP_DATA_DIR}/${cc_output_directory}/${cc_stderr_output_file}" \
        2>>"${TEMP_DATA_DIR}/${cc_output_directory}/${cc_stderr_output_file}"
      # remove output file if it is empty
      if [ ! -s "${TEMP_DATA_DIR}/${cc_output_directory}/${cc_output_file}" ]; then
        rm -f "${TEMP_DATA_DIR}/${cc_output_directory}/${cc_output_file}" \
          >/dev/null
      fi
    else
      if "${cc_compress_output_file}" && ${GZIP_TOOL_AVAILABLE}; then
        # run command and append output to compressed file
        log_message COMMAND "${cc_command} | gzip - | cat -"
        eval "${cc_command} | gzip - | cat -" \
          >>"${TEMP_DATA_DIR}/${cc_output_directory}/${cc_output_file}.gz" \
          2>>"${TEMP_DATA_DIR}/${cc_output_directory}/${cc_stderr_output_file}"
      else
        # run command and append output to existing file
        log_message COMMAND "${cc_command}"
        eval "${cc_command}" \
          >>"${TEMP_DATA_DIR}/${cc_output_directory}/${cc_output_file}" \
          2>>"${TEMP_DATA_DIR}/${cc_output_directory}/${cc_stderr_output_file}"
        # remove output file if it is empty
        if [ ! -s "${TEMP_DATA_DIR}/${cc_output_directory}/${cc_output_file}" ]; then
          rm -f "${TEMP_DATA_DIR}/${cc_output_directory}/${cc_output_file}" \
            >/dev/null
        fi
      fi
    fi

    # remove stderr output file if it is empty
    if [ ! -s "${TEMP_DATA_DIR}/${cc_output_directory}/${cc_stderr_output_file}" ]; then
      rm -f "${TEMP_DATA_DIR}/${cc_output_directory}/${cc_stderr_output_file}" \
        >/dev/null
    fi

  fi

}