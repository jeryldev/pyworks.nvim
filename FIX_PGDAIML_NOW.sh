#!/bin/bash

# Quick fix for pgdaiml kernel issue

echo "Fixing pgdaiml kernel..."
echo "Installing essential packages in pgdaiml virtual environment..."

# Install essential packages
/Users/jeryldev/code/pgdaiml/.venv/bin/python3 -m pip install \
    pynvim \
    ipykernel \
    jupyter_client \
    jupytext \
    ipython \
    notebook

if [ $? -eq 0 ]; then
    echo "✓ Successfully installed essential packages!"
    echo "The pgdaiml kernel should now work without errors."
else
    echo "✗ Failed to install packages. Check if the path is correct:"
    echo "  /Users/jeryldev/code/pgdaiml/.venv/bin/python3"
fi