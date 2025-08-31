# Pyworks.nvim Test Suite

This folder contains comprehensive test scenarios for pyworks.nvim's smart detection logic.

## Quick Start

1. **Generate test scenarios:**
   ```bash
   ./create_test_scenarios.sh
   ```
   This creates a `scenarios/` folder with 20+ test cases

2. **Test a scenario:**
   ```bash
   cd scenarios/04_django_project
   nvim myapp/views/user.py
   ```

3. **What to expect:**
   - Pyworks will show project type detection
   - It will indicate where venv exists or will be created
   - For missing venv, it suggests running `:PyworksSetup`

## Test Categories

### Python Projects
- `01_python_simple` - Basic Python file, no markers
- `02_python_with_venv` - Python with existing .venv
- `03_python_nested` - Nested file with parent venv

### Web Frameworks
- `04_django_project` - Django with manage.py
- `05_flask_project` - Flask with app.py
- `06_fastapi_project` - FastAPI with main.py
- `07_streamlit_project` - Streamlit dashboard

### Package Management
- `08_poetry_project` - Poetry with pyproject.toml
- `09_pipenv_project` - Pipenv with Pipfile
- `10_conda_project` - Conda with environment.yml

### MLOps/Data Science
- `13_dvc_project` - DVC pipeline project
- `14_mlflow_project` - MLflow experiment tracking

### Notebooks
- `21_standalone_notebook` - Simple .ipynb file
- `24_django_notebooks` - Django + deeply nested notebooks
- `25_fastapi_ml` - FastAPI + ML notebooks

### Other Languages
- `31_julia_project` - Julia with Project.toml
- `34_julia_notebook` - Julia notebook
- `41_r_renv_project` - R with renv.lock
- `44_r_notebook` - R notebook

### Edge Cases
- `51_multiple_markers` - Multiple project markers (tests priority)
- `55_mixed_language` - Python + Julia + R in same project

## Expected Behaviors

### With Existing Venv
```
🐍 Django project: venv at 04_django_project/.venv
```

### Without Venv
```
⚠️ FastAPI project: No venv for api/endpoints/predict.py
💡 Run :PyworksSetup to create venv at: 06_fastapi_project/.venv
```

### Notebooks in Projects
```
📓 Django notebook: venv at 04_django_project/.venv
```
Even deeply nested notebooks find the project root!

## Testing Workflow

1. Open file in test scenario
2. Check notifications (bottom of screen)
3. Try `:PyworksSetup` if no venv
4. Restart Neovim after setup
5. Verify Molten commands work

## Notes

- The `scenarios/` folder is gitignored to keep repo clean
- Run `./create_test_scenarios.sh` anytime to regenerate
- Each scenario is self-contained for easy testing