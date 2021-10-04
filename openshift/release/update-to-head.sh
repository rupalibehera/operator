#!/usr/bin/env bash

# Synchs the release-next branch to master and then triggers CI
# Usage: update-to-head.sh

set -ex
OPENSHIFT_REMOTE=${OPENSHIFT_REMOTE:-openshift}
PIPELINE_VERSION=${PIPELINE_VERSION:-nightly}
TRIGGERS_VERSION=${TRIGGERS_VERSION:-nightly}
CATALOG_RELEASE_BRANCH=${CATALOG_RELEASE_BRANCH:-release-next}
# RHOSP (Red Hat OpenShift Pipelines)
RHOSP_VERSION=${RHOSP_VERSION:-$(date  +"%Y.%-m.%-d")-nightly}
RHOSP_PREVIOUS_VERSION=${RHOSP_PREVIOUS_VERSION:-1.5.2}
OLM_SKIP_RANGE=${OLM_SKIP_RANGE:-\'>=1.5.0 <1.6.0\'}
LABEL=nightly-ci

function get_buildah_task() {
# The fetch task script will not pull buildah task from github repository
# as we have have made modifications in the buildah task in operator repository
# This function will preserve the buildah task from the previous release (clusterTask payload)
    buildah_dest_dir="cmd/openshift/operator/kodata/tekton-addon/${RHOSP_VERSION}/addons/02-clustertasks/buildah"
    mkdir -p ${buildah_dest_dir} || true
    task_path=${buildah_dest_dir}/buildah-task.yaml
    version_suffix="${RHOSP_VERSION//./-}"
    task_version_path=${buildah_dest_dir}/buildah-${version_suffix}-task.yaml

    cp -r cmd/openshift/operator/kodata/tekton-addon/1.5.0/addons/02-clustertasks/buildah/buildah-task.yaml ${buildah_dest_dir}
    sed \
        -e "s|^\(\s\+name:\)\s\+\(buildah\)|\1 \2-$RHOSP_VERSION|g"  \
        $task_path  > "$task_version_path"
}

# Reset release-next to upstream/main.
git fetch upstream main
git checkout upstream/main --no-track -B release-next

# Update openshift's master and take all needed files from there.
git fetch ${OPENSHIFT_REMOTE} master
git checkout FETCH_HEAD openshift OWNERS_ALIASES OWNERS .tekton

# Add payload
make get-releases TARGET='openshift' \
                  PIPELINES=${PIPELINE_VERSION} \
                  TRIGGERS=${TRIGGERS_VERSION}

# handle buildah task separately
get_buildah_task
# pull tasks
./hack/openshift/update-tasks.sh ${CATALOG_RELEASE_BRANCH} cmd/openshift/operator/kodata/tekton-addon/${RHOSP_VERSION} ${RHOSP_VERSION}

# generate csv
BUNDLE_ARGS="--workspace operatorhub/openshift \
             --operator-release-version ${RHOSP_VERSION} \
             --channels stable,preview \
             --default-channel stable \
             --fetch-strategy-local \
             --upgrade-strategy-replaces \
             --operator-release-previous-version ${RHOSP_PREVIOUS_VERSION} \
             --olm-skip-range ${OLM_SKIP_RANGE}"

make operator-bundle

git add openshift OWNERS_ALIASES OWNERS cmd/openshift/operator/kodata operatorhub/openshift
git commit -m ":open_file_folder: Update openshift specific files."

git push -f ${OPENSHIFT_REMOTE} release-next

# Trigger CI
git checkout release-next -B release-next-ci
date > ci
git add ci
git commit -m ":robot: Triggering CI on branch 'release-next' after synching to upstream/master"
git push -f ${OPENSHIFT_REMOTE} release-next-ci

# removing upstream remote so that hub points origin for hub pr list command due to this issue https://github.com/github/hub/issues/1973
git remote remove upstream
already_open_github_issue_id=$(hub pr list -s open -f "%I %l%n"|grep ${LABEL}| awk '{print $1}'|head -1)
[[ -n ${already_open_github_issue_id} ]]  && {
    echo "PR for nightly is already open on #${already_open_github_issue_id}"
    #hub api repos/${OPENSHIFT_ORG}/${REPO_NAME}/issues/${already_open_github_issue_id}/comments -f body='/retest'
    exit
}

hub pull-request -m "🛑🔥 Triggering Nightly CI for ${REPO_NAME} 🔥🛑" -m "/hold" -m "Nightly CI do not merge :stop_sign:" \
    --no-edit -l "${LABEL}" -b ${OPENSHIFT_ORG}/${REPO_NAME}:release-next -h ${OPENSHIFT_ORG}/${REPO_NAME}:release-next-ci

# This fix is required while running locally, otherwise your upstream remote is removed
git remote add upstream git@github.com:tektoncd/operator.git
