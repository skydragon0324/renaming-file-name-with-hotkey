# Special Rename

Small Windows utility that renames the currently selected File Explorer item when you press `Ctrl+F1` or `Ctrl+F2`.

## Run

From PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\SpecialRename.ps1
```

## Use

1. Start the app.
2. Enter the first and second target names.
3. Click `Start hotkey`.
4. In File Explorer, select exactly one file or folder.
5. Press `Ctrl+F1` to use the first target name, or `Ctrl+F2` to use the second target name.

For files, if the target name has no extension, the original extension is preserved. For example, `photo.jpg` with target name `target` becomes `target.jpg`.

The app will skip the rename if another file or folder with the target name already exists.
