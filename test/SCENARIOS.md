# Pyworks.nvim Test Scenarios

## All Scenarios Covered by Smart Logic

### 1. Python Files (.py)

#### Basic Scenarios
- **1.1 Simple Python file (no markers)**: Creates venv in file's directory
- **1.2 Python file with existing venv**: Uses found venv
- **1.3 Python file in subdirectory with parent venv**: Walks up and finds parent venv

#### Web Framework Projects
- **1.4 Django project (nested file)**: Finds manage.py, uses project root
- **1.5 Flask project**: Finds app.py with Flask imports
- **1.6 FastAPI project**: Finds main.py with FastAPI imports
- **1.7 Streamlit dashboard**: Finds app.py with streamlit imports

#### Package/Dependency Management
- **1.8 Poetry project**: Finds pyproject.toml
- **1.9 Pipenv project**: Finds Pipfile
- **1.10 Conda project**: Finds environment.yml or conda.yaml
- **1.11 Traditional pip project**: Finds requirements.txt
- **1.12 Python package**: Finds setup.py or setup.cfg

#### MLOps/Data Science
- **1.13 DVC project**: Finds dvc.yaml or .dvcignore
- **1.14 MLflow project**: Finds mlflow.yaml
- **1.15 Generic ML project**: Finds combination of notebooks + requirements.txt

### 2. Jupyter Notebooks (.ipynb)

#### Basic Notebook Scenarios
- **2.1 Standalone notebook (no markers)**: Creates venv in notebook's directory
- **2.2 Notebook with existing venv**: Uses found venv
- **2.3 Deeply nested notebook**: Walks up to find project root

#### Notebooks in Web Projects
- **2.4 Django + notebooks**: notebooks/experiments/analysis.ipynb → finds Django root
- **2.5 FastAPI + ML notebooks**: research/notebooks/train.ipynb → finds FastAPI root
- **2.6 Flask + data notebooks**: analysis/explore.ipynb → finds Flask root
- **2.7 Streamlit + notebooks**: dashboards/metrics.ipynb → finds Streamlit root

#### Notebooks in ML Projects
- **2.8 DVC pipeline notebooks**: notebooks/eda/explore.ipynb → finds DVC root
- **2.9 MLflow experiment notebooks**: experiments/train.ipynb → finds MLflow root
- **2.10 Conda environment notebooks**: Uses conda environment.yml location

### 3. Edge Cases

- **3.1 Multiple markers**: Prioritizes .venv > pyproject.toml > manage.py > requirements.txt
- **3.2 Git repository**: Uses .git as last resort for project root
- **3.3 Symlinked files**: Resolves to actual file location
- **3.4 No markers at all**: Uses file's immediate directory

## Project Type Detection Priority

1. `.venv/` - Existing virtual environment (highest priority)
2. `manage.py` - Django project
3. `app.py` - Flask/Streamlit (checks imports)
4. `main.py` - FastAPI (checks imports)
5. `dvc.yaml` - DVC/MLOps project
6. `mlflow.yaml` - MLflow project
7. `pyproject.toml` - Poetry/Modern Python
8. `setup.py` - Python package
9. `Pipfile` - Pipenv project
10. `environment.yml`/`conda.yaml` - Conda project
11. `requirements.txt` - Traditional Python project
12. `setup.cfg` - Python package config
13. `tox.ini` - Testing project
14. `.dvcignore` - DVC project
15. `uv.lock` - UV project
16. `.git/` - Git repository (lowest priority)

## Expected Behaviors

### When venv EXISTS:
- Shows: "🐍 [ProjectType] project: venv at [path]/.venv"
- Uses existing venv
- Sets Python host
- Checks for essential packages

### When venv MISSING:
- Shows: "⚠️ [ProjectType] project: No venv for [file]"
- Shows: "💡 Run :PyworksSetup to create venv at: [path]/.venv"
- Does NOT auto-create
- Molten commands show helpful error

### After :PyworksSetup:
- Creates venv at detected project root
- Installs essentials: pynvim, ipykernel, jupyter_client, jupytext
- Sets up Python host
- Ready for code execution
