set -euxo pipefail

apt-get update
apt-get install cpanminus build-essential libfile-copy-recursive-perl libxml-parser-perl fpc -y
cpanm --installdeps .

# Configure proxy properly!
# Replace delphi with fpc
