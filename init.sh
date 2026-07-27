#!/usr/bin/env bash
set -euo pipefail

# Colors for better terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==> Initializing vala-downloader-lib dependency...${NC}"

# 1. Check if the user is running the script in the root of a Meson project
if [ ! -f "meson.build" ]; then
    echo -e "${RED}[Error] 'meson.build' file not found in the current directory.${NC}"
    echo -e "Make sure you are running this script in the root folder of your Vala application."
    exit 1
fi

# 2. Create the subprojects folder if it doesn't exist yet
if [ ! -d "subprojects" ]; then
    echo -e "Creating ${BLUE}subprojects/${NC} directory..."
fi
mkdir -p "subprojects"

# 3. Generate the .wrap file
WRAP_FILE="subprojects/vala-downloader-lib.wrap"
echo -e "Generating wrap file ${BLUE}${WRAP_FILE}${NC}..."

cat << 'EOF' > "$WRAP_FILE"
[wrap-git]
url = https://github.com/ValaTux/downloader-lib.git
revision = master
depth = 1

[provide]
vala_downloader = vala_downloader_dep
EOF

echo -e "${GREEN}[Done] Wrap file has been successfully created.${NC}\n"

# 4. Instructions for the developer on how to proceed
echo -e "${BLUE}Now edit your main 'meson.build' and add the dependency:${NC}"
echo -e "--------------------------------------------------------"
echo -e "vala_downloader_dep = dependency('vala_downloader', fallback: ['vala-downloader-lib', 'vala_downloader_dep'])"
echo -e ""
echo -e "executable("
echo -e "  'your-binary-name',"
echo -e "  'your-source-files.vala',"
echo -e "  dependencies: [ dependency('glib-2.0'), dependency('gio-2.0'), dependency('libsoup-3.0'), ${GREEN}vala_downloader_dep${NC} ]"
echo -e ")"
echo -e "--------------------------------------------------------"
echo -e "Then build the project using:"
echo -e "${GREEN}meson setup builddir && meson compile -C builddir${NC}"
