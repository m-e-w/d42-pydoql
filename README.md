# d42-pydoql
A simple python script that:
 1. Reads a .sql file
 2. Queries a Device42 instance
 4. Saves the response

Fin.

# Example Usage
```
python doql.py sql/prod/all_devices.sql
```

# Setup
1. Install python (tested with 3.10.4)
2. (Recommended) Create virtual environment
    - See https://docs.python.org/3/tutorial/venv.html for information on creating and activating virtual environments.
3. Install required packages
    ```
    pip install -r requirements.txt
    ```
4. Rename **config.json.sample** to **config.json** and replace settings with your own.
5. Test it out
    - Change to the root directory and call:
        ```
        python doql.py sql/prod/all_devices.sql
        ```
    - If everything works you should see a .csv file saved to the output path defined in the config file
# Advanced Usage
## Custom Keyboard Shortcut in Visual Studio Code
1. Open the keybindings.json file from the Command Palette (Ctrl+Shift+P) with the Preferences: Open Keyboard Shortcuts (JSON) command.
2. Copy the block below into your keybindings.json file
```
// Place your key bindings in this file to override the defaults
[
    {
        "key": "ctrl+shift+t",
        "command": "workbench.action.terminal.sendSequence",
        "args": {
            "text": "python ~/Source/Repos/d42-pydoql/doql.py '${file}'\u000D"
        }
    },
    {
        "key": "ctrl+shift+t",
        "command": "-workbench.action.reopenClosedEditor"
    }
]
```
3. Replace: **~/Source/Repos/d42-pydoql/doql.py** with your own path.
4. Select a .sql file in Visual Studio Code and type **ctrl + shift + t**
    - **Note** You need to have an open terminal. (View -> Terminal)
    - If everything works you should see a .csv file saved to the output path defined in the config file


