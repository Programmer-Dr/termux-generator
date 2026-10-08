# Function to validate the package name
check_names() {
    if [[ $TERMUX_APP__PACKAGE_NAME =~ '_' ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME =~ '-' ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == package ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == package.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.package ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.package.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == in ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == in.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.in ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.in.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == is ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == is.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.is ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.is.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == as ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == as.* ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.as ]] || \
       [[ $TERMUX_APP__PACKAGE_NAME == *.as.* ]]
    then
        echo "[!] Package name must not contain underscores, dashes, or invalid patterns!"
        exit 2
    fi

    if [[ $TERMUX_APP__PACKAGE_NAME == *"com.termux"* ]] && \
        [[ "$TERMUX_APP__PACKAGE_NAME" != "com.termux" ]]; then
        echo "[!] Sorry, please choose a unique custom name that does not contain 'com.termux'"
        echo "(and is not an exact substring of it either) to avoid side effects."
        echo "Examples: 'com.test.termux' is OK, but 'com.termux.test' or 'com.ter' could have side effects."
        exit 2
    fi

    if [[ $ADDITIONAL_PACKAGES == *"termux-x11-nightly"* ]]; then
        echo "[!] That version of termux-x11-nightly is precompiled and"
        echo "cannot be compiled by termux-generator with any custom name inserted!"
        echo "To use termux-x11-nightly with termux-generator, just set"
        echo "'--type f-droid', then install the .apk files termux-generator builds."
        echo "A source-built and patched 'termux-x11-nightly' package is"
        echo "automatically preinstalled."
        exit 2
    fi
}

clean_docker() {
    docker container kill "$TERMUX_GENERATOR_CONTAINER_NAME" 2> /dev/null || true
    docker container rm -f "$TERMUX_GENERATOR_CONTAINER_NAME" 2>/dev/null || true
    if ! docker image rm ghcr.io/termux/package-builder 2>/dev/null; then
        echo "[*] Warning: not removing Docker package builder image for \"F-Droid\" Termux, likely because it is either not downloaded yet, or in use by other containers."
    fi
    if ! docker image rm ghcr.io/termux-play-store/package-builder 2>/dev/null; then
        echo "[*] Warning: not removing Docker package builder image for \"Google Play\" Termux, likely because it is either not downloaded yet, or in use by other containers."
    fi
}

clean_artifacts() {
    rm -rf termux* *.apk *.deb *.xz *.zip 2>/dev/null
}

# ---------------------------------------------------------------------------
# Upstream PRs that are NOT yet merged into master of termux-app.
# Keep this list as URLs to .patch files on GitHub.
# ---------------------------------------------------------------------------
UPSTREAM_TERMUX_APP_PRS=(
    5179   # Native RTL text rendering + Arabic/Persian/Urdu/Hebrew shaping
)

# Apply the upstream PRs listed above by fetching each PR's head commit
# into the local clone and checking out the files the PR touches.
#
# This avoids both `git apply` (which fails when the PR's base drifts)
# and raw.githubusercontent.com (which 404s for files only reachable
# through refs/pull/N/head).
apply_upstream_pr_patches() {
    local app_dir="$1"
    local repo="termux/termux-app"
    local repo_url="https://github.com/$repo.git"

    [ -d "$app_dir" ] || return 0

    pushd "$app_dir" >/dev/null

    local pr
    for pr in "${UPSTREAM_TERMUX_APP_PRS[@]}"; do
        echo "[*] Applying upstream PR #$pr (git fetch + selective checkout)"

        # 1. Fetch the PR head into a local remote-tracking ref.
        if ! git fetch --no-tags "$repo_url" "refs/pull/$pr/head:refs/remotes/pr/$pr"; then
            echo "[!]   Could not fetch PR #$pr from $repo_url"
            popd >/dev/null
            exit 3
        fi

        local pr_ref="refs/remotes/pr/$pr"
        local head_sha
        head_sha=$(git rev-parse "$pr_ref")
        echo "[*]   PR #$pr head SHA: $head_sha"

        # 2. Get the list of files the PR touches, from its patch.
        #    We can't use `git diff HEAD $pr_ref` because that also shows
        #    every file master has changed since the PR's base — checking
        #    those out would silently roll master back.
        local patch_file files
        patch_file="$(mktemp)"
        if ! curl -fsSL "https://github.com/$repo/pull/$pr.patch" -o "$patch_file"; then
            echo "[!]   Could not download patch for PR #$pr"
            rm -f "$patch_file"
            popd >/dev/null
            exit 3
        fi

        files=$(grep -E '^\+\+\+ b/' "$patch_file" \
                | sed 's|^+++ b/||' \
                | grep -v '^/dev/null$' \
                | sort -u)
        rm -f "$patch_file"

        if [ -z "$files" ]; then
            echo "[!]   No files found in PR #$pr patch"
            popd >/dev/null
            exit 3
        fi

        echo "[*]   Files touched by PR #$pr:"
        echo "$files" | sed 's/^/        /'

        # 3. Checkout each touched file from the PR head.
        local f
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            case "$f" in
                .github/*)
                    echo "        [skip] $f (workflow file)"
                    continue
                    ;;
            esac
            echo "        [checkout] $f"
            if ! git checkout "$pr_ref" -- "$f"; then
                echo "        [!] Failed to checkout $f from PR head"
                popd >/dev/null
                exit 3
            fi
        done <<< "$files"

        echo "[*]   PR #$pr applied."
    done

    popd >/dev/null
}

# Function to download repositories
download() {
    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        git clone --depth 1 https://github.com/termux/termux-packages.git               termux-packages-main
        git clone --depth 1 https://github.com/termux/termux-tasker.git                 termux-apps-main/termux-tasker
        git clone --depth 1 https://github.com/termux/termux-float.git                  termux-apps-main/termux-float
        git clone --depth 1 https://github.com/termux/termux-widget.git                 termux-apps-main/termux-widget
        git clone --depth 1 https://github.com/termux/termux-api.git                    termux-apps-main/termux-api
        git clone --depth 1 https://github.com/termux/termux-boot.git                   termux-apps-main/termux-boot
        git clone --depth 1 https://github.com/termux/termux-styling.git                termux-apps-main/termux-styling
        git clone --depth 1 https://github.com/termux/termux-app.git                    termux-apps-main/termux-app
        git clone --depth 1 https://github.com/termux/termux-gui.git                    termux-apps-main/termux-gui

        # Apply the RTL PR (and any other unmerged upstream PRs) right after the
        # clone and before the termux-am-library is moved in, so the patch sees
        # the exact upstream master tree it was written against.
        apply_upstream_pr_patches termux-apps-main/termux-app

        # special case - for "F-Droid" Termux, it is necessary to move the termux-am-library subfolder of
        # the termux-am-library repository, which contains its actual code, into the termux-app folder,
        # where its code needs to be patched and compiled into the main "F-Droid" Termux APK
        git clone --depth 1 https://github.com/termux/termux-am-library.git             termux-apps-main/termux-am-library
        mv termux-apps-main/termux-am-library/termux-am-library/                        termux-apps-main/termux-app/termux-am-library
        rm -rf                                                                          termux-apps-main/termux-am-library/
    else
        git clone --depth 1 https://github.com/termux-play-store/termux-packages.git    termux-packages-main
        git clone --depth 1 https://github.com/termux-play-store/termux-apps.git        termux-apps-main
        apply_upstream_pr_patches termux-apps-main/termux-app
    fi
    git clone --depth 1 --recursive https://github.com/termux/termux-x11.git        termux-apps-main/termux-x11
}

install_plugin() {
    apply_patches "plugins/$TERMUX_GENERATOR_PLUGIN/$TERMUX_APP_TYPE-patches/bootstrap-patches" termux-packages-main
    apply_patches "plugins/$TERMUX_GENERATOR_PLUGIN/$TERMUX_APP_TYPE-patches/app-patches" termux-apps-main
}

# Function to apply bootstrap patches
patch_bootstraps() {
    # The reason why it is necessary to replace the name first, then patch bootstraps, but do the reverse for apps,
    # is because command-not-found must be partially unpatched back to the default TERMUX_PREFIX to build,
    # so that patch must apply after the bootstraps' name replacement has completed, but the apps contain the
    # string "com.termux" in their code in many more places than the bootstraps do, so it's easier to patch them first.
    if [[ "$TERMUX_APP__PACKAGE_NAME" != "com.termux" ]]; then
        replace_termux_name termux-packages-main "$TERMUX_APP__PACKAGE_NAME"
    fi

    apply_patches "$TERMUX_APP_TYPE-patches/bootstrap-patches" termux-packages-main

    portable_sed_i -e "s|termux-package-builder|$TERMUX_GENERATOR_CONTAINER_NAME|g" termux-packages-main/scripts/run-docker.sh

    local bashrc="termux-packages-main/packages/bash/etc-bash.bashrc"

    if [[ -n "$ENABLE_SSH_SERVER" ]]; then
        cat <<- EOF >> "$bashrc"
            if [ ! -f "\$HOME/.termux/boot/start-sshd" ]; then
                mkdir -p "\$HOME/.termux/boot"
                echo '#!/data/data/$TERMUX_APP__PACKAGE_NAME/files/usr/bin/sh' > "\$HOME/.termux/boot/start-sshd"
                echo '. /data/data/$TERMUX_APP__PACKAGE_NAME/files/usr/etc/bash.bashrc' >> "\$HOME/.termux/boot/start-sshd"
                chmod +x "\$HOME/.termux/boot/start-sshd"
            fi
            if [ ! -f "\$HOME/.termux_authinfo" ]; then
                printf '$DEFAULT_PASSWORD\n$DEFAULT_PASSWORD' | passwd
            fi
            sshd
EOF
    fi

    cp -f "$TERMUX_GENERATOR_HOME/scripts/termux_generator_utils.sh" termux-packages-main/scripts/

    # remove packages that are severely broken in ways that corrupt
    # the container, other packages, or the boostrap second stage if they are allowed to be built
    # I keep track of these, so contact me if you think it's time to remove one from this blocklist
    rm -rf termux-packages-main/packages/swift # https://github.com/termux/termux-packages/issues/26246
    rm -rf termux-packages-main/packages/zeronet # https://github.com/termux/termux-packages/pull/25367
}

# Function to patch the app
patch_apps() {
    apply_patches "$TERMUX_APP_TYPE-patches/app-patches" termux-apps-main

    if [[ "$TERMUX_APP__PACKAGE_NAME" == "com.termux" ]]; then
        return
    fi

    replace_termux_name termux-apps-main "$TERMUX_APP__PACKAGE_NAME"

    migrate_termux_folder_tree termux-apps-main "$TERMUX_APP__PACKAGE_NAME"
}

build_termux_x11() {
    pushd termux-apps-main/termux-x11
    ./gradlew assembleDebug
    popd
}

move_termux_x11_deb() {
    pushd termux-apps-main/termux-x11

    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local termux_x11_dest="$TERMUX_GENERATOR_HOME/termux-packages-main/output"
    else
        local termux_x11_dest="$TERMUX_GENERATOR_HOME/termux-packages-main"
    fi

    mkdir -p "$termux_x11_dest"
    mv shell-loader/build/outputs/companion/*.deb "$termux_x11_dest/termux-x11-nightly_all.deb"

    popd
}

# Function to build bootstraps
build_bootstraps() {
    pushd termux-packages-main

    local bootstrap_script_args=""

    if [ -n "$ENABLE_SSH_SERVER" ]; then
        ADDITIONAL_PACKAGES+=",openssh"
    fi

    bootstrap_script_args+=" --add ${ADDITIONAL_PACKAGES}"

    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local bootstrap_script="build-bootstraps.sh"
        local bootstrap_architectures="aarch64,x86_64,arm,i686"
        if [ -n "${DISABLE_BOOTSTRAP_SECOND_STAGE-}" ]; then
            bootstrap_script_args+=" --disable-bootstrap-second-stage"
        fi
    else
        local bootstrap_script="generate-bootstraps.sh"
        local bootstrap_architectures="aarch64,x86_64,arm"
        bootstrap_script_args+=" --build"
    fi

    if [ -n "${BOOTSTRAP_ARCHITECTURES}" ]; then
        bootstrap_architectures="$BOOTSTRAP_ARCHITECTURES"
    fi

    bootstrap_script_args+=" --architectures $bootstrap_architectures"

    if [[ "${CI-}" == "true" ]]; then
        scripts/free-space.sh
    fi

    # Replace symbolic link /system which is inside the termux-package-builder docker image
    # pointed to /data/data/com.termux/aosp by default
    # https://github.com/termux/termux-packages/blob/650907de80114cc53b20b181161f993e3ad0dfad/scripts/setup-ubuntu.sh#L371
    # needed for building pypy and similar packages
    scripts/run-docker.sh sudo ln -sf "/data/data/$TERMUX_APP__PACKAGE_NAME/aosp" /system

    if [[ "$TERMUX_APP_TYPE" == "f-droid" && "$TERMUX_APP__PACKAGE_NAME" == "com.retired64.termux" && $bootstrap_architectures != *","* ]]; then
        build_all_packages "$bootstrap_architectures"
    fi

    rm -rf .github/workflows/*
    sed -e "s|@TERMUX_APP__PACKAGE_NAME@|$TERMUX_APP__PACKAGE_NAME|g" \
        -e "s|@BOOTSTRAP_BUILD_COMMAND@|scripts/$bootstrap_script $bootstrap_script_args|g" \
        "$TERMUX_GENERATOR_HOME/scripts/build-bootstraps.yml.in" \
        > .github/workflows/build-bootstraps.yml

    scripts/run-docker.sh "scripts/$bootstrap_script" $bootstrap_script_args

    popd
}

# Function to move bootstraps
move_bootstraps() {
    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local app_assets_dir="app/src/main/assets/"
    else
        local app_assets_dir="src/main/assets/"
    fi
    if [ -z "${DISABLE_TERMINAL}" ]; then
        mkdir -p "termux-apps-main/termux-app/$app_assets_dir"
        mv termux-packages-main/bootstrap-* "termux-apps-main/termux-app/$app_assets_dir"
        if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
            mv termux-packages-main/xz-* "termux-apps-main/termux-app/$app_assets_dir"
        fi
    else
        for zip in termux-packages-main/bootstrap-*; do
            mv "$zip" "$TERMUX_APP__PACKAGE_NAME-$TERMUX_APP_TYPE-$(basename $zip)"
        done
    fi
}

# Function to build the app
build_apps() {
    pushd termux-apps-main

    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        if [ -z "${DISABLE_TERMINAL}" ]; then
            pushd termux-app
                ./gradlew publishReleasePublicationToMavenLocal
            popd
        fi
        for app in *; do
            if [[ "$app" == "termux-app" ]] && [[ -n "${DISABLE_TERMINAL}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-tasker" ]] && [[ -n "${DISABLE_TASKER}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-float" ]] && [[ -n "${DISABLE_FLOAT}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-widget" ]] && [[ -n "${DISABLE_WIDGET}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-api" ]] && [[ -n "${DISABLE_API}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-boot" ]] && [[ -n "${DISABLE_BOOT}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-styling" ]] && [[ -n "${DISABLE_STYLING}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-gui" ]] && [[ -n "${DISABLE_GUI}" ]]; then
                continue
            fi
            if [[ "$app" == "termux-x11" ]]; then
                continue
            fi
            pushd "$app"
                ./gradlew assembleDebug
            popd
        done
    else
        if [[ "${CI-}" == "true" ]]; then
            export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
            sudo update-alternatives --set java "$JAVA_HOME/bin/java"
        fi
        ./gradlew assembleDebug
    fi

    popd
}

# Function to move APKs
move_apks() {
    if [[ "$TERMUX_APP_TYPE" == "f-droid" ]]; then
        local build_dir="app/build/outputs/apk/debug"
    else
        local build_dir="build/outputs/apk/debug"
    fi

    if [ -z "${DISABLE_X11}" ]; then
        for apk in termux-apps-main/termux-x11/lorie-app/build/outputs/apk/*/debug/*.apk; do
            mv "$apk" "$TERMUX_APP__PACKAGE_NAME-$TERMUX_APP_TYPE-$(basename $apk)"
        done
    fi

    if [[ -z "${DISABLE_TERMINAL}" ]] || \
        [[ -z "${DISABLE_TASKER}" ]] || \
        [[ -z "${DISABLE_FLOAT}" ]] || \
        [[ -z "${DISABLE_WIDGET}" ]] || \
        [[ -z "${DISABLE_API}" ]] || \
        [[ -z "${DISABLE_BOOT}" ]] || \
        [[ -z "${DISABLE_STYLING}" ]] || \
        [[ -z "${DISABLE_GUI}" ]]; then
        for apk in termux-apps-main/*/"$build_dir"/*.apk; do
            mv "$apk" "$TERMUX_APP__PACKAGE_NAME-$TERMUX_APP_TYPE-$(basename $apk)"
        done
    fi
}


