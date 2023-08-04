#!/bin/bash
set -e

check_requirements() {
  local cmds=(curl koji mkfifo tail awk xmllint grep git sed fedpkg)
  local missing_commands=()
  for cmd in "${cmds[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_commands+=("$cmd")
    fi
  done
  if [ ${#missing_commands[@]} -eq 0 ]; then
    return 0
  else
    echo "Missing commands:"
    for missing_cmd in "${missing_commands[@]}"; do
      echo "  $missing_cmd"
    done
    return 1
  fi
}

show_help() {
  echo "Tools to find out what packages depend on specific requires
Usage:
  $0 -t <tag> -r <requires> [options]

Options:
  --tag (-t) <tag_name>
      (Required) Only packages belonging to the specified Koji tag will be processed.

  --search (-s) <regex_pattern>
      Only packages matching the given regex will be processed.

  --requires (-r) <regex_pattern>
      (Required) A package is matched when a package's 'requires' matches the specified regex.

  --branch (-b) <fedora_branch>
      Checkout specified branch during packaging.

  --rebuild
      Automatically trigger a rebuild for matched packages.

  --nobuild
      Do not automatically trigger a rebuild for matched packages.

  --output (-o) <file>
      Output the list of matched packages to the specified file.

  --profile (-p) <profile_name>
      Use the specified profile in Koji commands (-p).

  --url (-u) <koji_hub_url>
      Specify the URL root of the Koji hub.

  --concurrency (-c) <num_threads>
      Set the number of concurrent threads for processing.

  --timeout <seconds>
      Set the timeout for curl operations, in seconds.

  "
}

retry() {
  local -r max_attempts=5
  local attempt=0
  local cmd=("$@")

  while ((attempt < max_attempts))
  do
    local output
    if output=$("${cmd[@]}" 2>&1); then
      echo "$output"
      return 0
    fi

    ((attempt++))
    printf "[!] Attempt $attempt failed. Retrying.\n" 1>&2

    if ((attempt == max_attempts)); then
      printf "[!] Reached the maximum number of attempts. Giving up.\n" 1>&2
      return 0
    fi
  done
}


rebuild=true
url_root="http://openkoji.iscas.ac.cn/koji"
thread=4
timeout=5

while (( "$#" )); do
  case "$1" in
    --tag|-t)
      tag=$2
      shift 2
      ;;
    --search|-s)
      search=$2
      shift 2
      ;;
    --requires|-r)
      requires=$2
      shift 2
      ;;
    --branch|-b)
      branch=$2
      shift 2
      ;;
    --rebuild)
      rebuild=true
      shift 1
      ;;
    --nobuild)
      rebuild=false
      shift 1
      ;;
    --output|-o)
      output=$2
      shift 2
      ;;
    --profile|-p)
      profile=$2
      shift 2
      ;;
    --url|-u)
      url_root=$2
      shift 2
      ;;
    --concurrency|-c)
      thread=$2
      shift 2
      ;;
    --timeout)
      timeout=$2
      shift 2
      ;;
    --help)
      show_help
      ;;
    --)
      shift
      break
      ;;
    -*|--*=)
      echo "Error: Unsupported flag $1" >&2
      show_help
      exit 1
      ;;
  esac
done

check_requirements
[ $# -eq 0 ] && show_help && exit 1
[ -z "$requires" ] && echo "Please specify the regex for requires!" && show_help && exit 1
[ -z "$branch" ] && echo "Please specify the branch of the repo!" && show_help && exit 1
[ -z "$tag" ] || tag_param="--tag $tag"
[ -z "$profile" ] || profile_param="-p $profile"

echo "Parameters"
echo ""
echo "tag: $tag"
echo "search: $search"
echo "requires: $requires"
echo "rebuild: $rebuild"
echo "profile: $profile"
echo "url root: $url_root"
echo "output: $output"
echo "thread: $thread"
echo "=============================================="

# List packages
packages=$(koji $profile_param list-pkgs $tag_param | tail -n +3 | awk '{print $1}')

rm npipe || true
mkfifo npipe # create temp named pipe
exec 5<>npipe # link fd with named pipe

for i in `seq $thread`; do
    echo
done >&5

for package in $packages; do
    # Check if regex matches the package name
    if [ ! -z $search ]; then
        if [[ ! $package =~ $search ]]; then
            continue
        fi
    fi

    read -u5  # s.acquire()
    {
        echo "[*] Processing: $package"
        # Get package build
        last_line=$(koji $profile_param list-builds --package=$package --state=COMPLETE | tail -n +3 | tail -n 1)
        build_name=$(echo "$last_line" | awk '{print $1}')

        # No successful build
        if [ -z "$build_name" ]; then 
            echo "[-] No successful builds. Abort."
        else
            echo "[*] Sucessful build: $build_name"

            # Get rpms
            rpm_list=$(koji $profile_param buildinfo $build_name | awk -F '/' '$1 == 'mnt' {print $NF}')
            for rpm in $rpm_list; do
                # Filter rpm id
                rpm_id=$(koji $profile_param rpminfo $rpm | awk '$1 == "RPM:" {gsub(/[\[\]]/, "", $NF);print $NF}')
                echo "  [*] RPM: $rpm ID: $rpm_id"

                # Get rpm info
                rpm_info=$(retry curl -s -m $timeout $url_root/rpminfo?rpmID=$rpm_id)
                [ -z "$rpm_info" ] && continue
                rpm_requires=$(echo "$rpm_info" | xmllint --html --xpath '/html/body/div/div/div[3]/table//table[@class="nested"]//td/text()' -)
                deps=$(echo "$rpm_requires" | grep -E "$requires" || true)

                [ -z "$deps" ] && echo "  [-] Dependency not found." && continue

                echo "  [+] Dependencies found. $deps"
            
                [ -z "$output" ] || echo $package >> $output

                if [ "$rebuild" = true ]; then
                    rm -rf $package

                    # Clone from fedora source
                    git clone https://src.fedoraproject.org/rpms/$package.git
                    cd $package
                    [ -z $branch ] || git checkout $branch

                    # Insert rvrebuild to Release
                    # fixme: autorelease is not applicable to this method
                    sed -i 's/\([0-9a-zA-Z.-]*\)%{?dist}/\1.rvrebuild%{?dist}/' *.spec

                    # Build srpm
                    fedpkg srpm

                    # Calling koji to build
                    koji $profile_param build --nowait $tag *.src.rpm

                    cd ..
                fi

                # Since this package is being rebuilt, no longer need to check the remaning RPM
                break
            done

            echo "=============================================="
        fi
        echo >&5  # s.release()
    } & 2>&1
done

wait
