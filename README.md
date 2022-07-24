# ZEF_splitter

The program was created to split the files of the Schneider Electric Unity Pro project (EcoStruxure Control Expert) into many text and binary files. Splitting into text files is convenient for working with version control systems (GIT, Mercurial, etc).

The ["zef_splitter"](https://github.com/corax4/ZEF_splitter/releases/download/v0.6.0/zef_splitter.exe) does not require installation.

The program accepts a file of type XEF or ZEF as an argument. You can specify the file on the command line, shortcut options, or drag and drop the file onto the program. The "sources" parameter saves the source texts of the program next to the program in the file "zef_splitter sources.zip". A project can be exported to a ZEF file via the File menu in Unity Pro.

The program creates a folder next to the ZEF file with the file name and the ending _ZEF (_XEF for XEF files). If such a folder exists, it is cleared. The structure of the files inside the project corresponds to the project's XML file. 

Variables and constants are stored in three different files:

- var.xml contains variables and constants as in the source file. Since the order of variables in the file may change during export, such a file is inconvenient for version control. It is recommended to add it to the exceptions.
- var_sorted.xml contains the same variables and constants as in the source file, but sorted by name. Suitable for version control, but not convenient, since changes to arrays can be far from the array name.
- var.txt contains variables and constants sorted by name. Dot separation is used for structures. Each element of the array and structure contains the full name, so such a file is most convenient for tracking changes in version control systems.
