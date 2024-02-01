#!/bin/sh

__run_stylelint() {
  cmd="stylelint ${INPUT_STYLELINT_INPUT} --formatter json"

  if [ -n "${INPUT_STYLELINT_CONFIG}" ]; then
    cmd="${cmd} --config='${INPUT_STYLELINT_CONFIG}'"
  fi

  if [ -n "${INPUT_STYLELINT_IGNORE}" ]; then
    cmd="${cmd} --ignore-pattern='${INPUT_STYLELINT_IGNORE}'"
  fi

  npx --no-install -c "${cmd}"
}

__rdformat_filter() {
  input_filter='.[] | {source: .source, warnings:.warnings[]}'
  output_filter='\(.source):\(.warnings.line):\(.warnings.column):\(.warnings.severity): \(.warnings.text)'
  output_links_filter='[\(.warnings.rule)](\(if .warnings.rule | startswith("scss/") then "https://github.com/stylelint-scss/stylelint-scss/blob/master/src/rules/\(.warnings.rule | split("scss/") | .[1])/README.md" else "https://stylelint.io/user-guide/rules/\(.warnings.rule)" end))'

  if [ "${INPUT_REPORTER}" = 'github-pr-review' ]; then
    # Format results to include link to rule page.
    echo "${input_filter} | \"${output_filter} ${output_links_filter}\""
  else
    echo "${input_filter} | \"${output_filter}\""
  fi
}

__filter_json() {
  jq "$(__rdformat_filter)"
}

__run_reviewdog() {
  reviewdog -efm="%f:%l:%c:%t%*[^:]: %m" \
            -name="${INPUT_NAME}" \
            -reporter="${INPUT_REPORTER}" \
            -level="${INPUT_LEVEL}" \
            -filter-mode="${INPUT_FILTER_MODE}" \
            -fail-on-error="${INPUT_FAIL_ON_ERROR}"
}

cd "${GITHUB_WORKSPACE}/${INPUT_WORKDIR}" || exit 1

TEMP_PATH="$(mktemp -d)"
PATH="${TEMP_PATH}:$PATH"
export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN}"

echo '::group:: Installing reviewdog 🐶 ... https://github.com/reviewdog/reviewdog'
curl -sfL https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b "${TEMP_PATH}" "${REVIEWDOG_VERSION}" 2>&1
echo '::endgroup::'

npx --no-install -c 'stylelint --version'
if [ $? -ne 0 ]; then
  echo '::group:: Running `npm install` to install stylelint ...'
  npm install
  echo '::endgroup::'
fi

if [ -n "${INPUT_PACKAGES}" ]; then
  echo '::group:: Running `npm install` to install input packages ...'
  npm install ${INPUT_PACKAGES}
  echo '::endgroup::'
fi

echo "stylelint version: $(npx --no-install -c 'stylelint --version')"

echo '::group:: Running stylelint with reviewdog 🐶 ...'
__run_stylelint | __filter_json | __run_reviewdog

reviewdog_rc=$?
echo '::endgroup::'
exit $reviewdog_rc
