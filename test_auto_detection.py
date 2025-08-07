#!/usr/bin/env python3
"""Test file to verify automatic detection and kernel initialization"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# This file should trigger:
# 1. "Detected Python file - checking for Jupyter support..."
# 2. Kernel detection and initialization
# 3. Package detection showing missing packages
# 4. Prompt to install with <leader>pi

print("Testing automatic detection")