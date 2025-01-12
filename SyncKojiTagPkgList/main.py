import argparse
import koji
import sys
from tqdm import tqdm

def get_koji_session(koji_hub_or_profile):
    if koji_hub_or_profile.startswith(('http://', 'https://')):
        return koji.ClientSession(koji_hub_or_profile)
    else:
        koji_config = koji.read_config(profile_name=koji_hub_or_profile)
        session = koji.ClientSession(koji_config['server'], opts=koji_config)
        if koji_config.get('cert') and koji_config.get('ca') and koji_config.get('serverca'):
            session.ssl_login(koji_config['cert'], koji_config['ca'], koji_config['serverca'])
        else:
            session.gssapi_login()
        return session

def main():
    parser = argparse.ArgumentParser(description="Sync packages from one Koji tag to another.")
    parser.add_argument("source_koji", help="Source Koji hub URL or profile name.")
    parser.add_argument("source_tag", help="Source Koji tag.")
    parser.add_argument("target_koji", help="Target Koji hub URL or profile name.")
    parser.add_argument("target_tag", help="Target Koji tag.")
    parser.add_argument("--override-owner", help="Override the package owner to this value.", default=None)
    parser.add_argument("--dry-run", action="store_true", help="Print the actions that would be taken without executing them.")

    args = parser.parse_args()

    try:
        source_session = get_koji_session(args.source_koji)
        target_session = get_koji_session(args.target_koji)
    except Exception as e:
        print(f"Error creating Koji sessions: {e}")
        sys.exit(1)

    try:
        packages = source_session.listPackages(tagID=args.source_tag)
    except Exception as e:
        print(f"Error fetching packages from source tag: {e}")
        sys.exit(1)

    package_data = []
    for package in packages:
        package_info = {
            'package_id': package['package_id'],
            'package_name': package['package_name'],
            'owner': args.override_owner if args.override_owner else package['owner_name'],
            'blocked': package['blocked']
        }
        package_data.append(package_info)

    for package in tqdm(package_data, desc="Syncing packages", unit="package"):
        try:
            if args.dry_run:
                print(f"Would add package {package['package_name']} to tag {args.target_tag} with owner {package['owner']} and blocked status to {package['blocked']}")
            else:
                target_session.packageListAdd(args.target_tag, package['package_name'], owner=package['owner'], block=package['blocked'])
        except koji.GenericError as e:
            print(f"Error adding package {package['package_name']}: {e}")

    if args.dry_run:
        print("Dry run completed. No changes were made.")
    else:
        print("All packages have been synchronized.")

if __name__ == "__main__":
    main()

