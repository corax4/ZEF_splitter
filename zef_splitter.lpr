{
MIT License

Copyright (c) 2022 Yuri Lychakov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
}

program zef_splitter;

uses
    Classes,
    SysUtils,
    Windows,
    strutils,
    FileUtil,
    LazFileUtils,
    crt,
    zipper,
    laz2_DOM,
    laz2_XMLRead;

var
    rsSources: TResourceStream; // source
    zevName: string;    // ZEV or XEF file name
    zevPath: string;    // ZEV or XEF file path
    xevText: string;    // text from XEV-file
    outText: string;    // text for save to file
    txt: string;        // extracted text
    outPath: string;    // output folder
    efTxt: string;      // extracted EFSource parts
    efbTxt: string;     // extracted EFBSource parts
    fbName: string;     // name of FBT
    progName: string;   // program section name
    stTxt: string;      // ST text
    sl: TStringList;    // StringList for R/W text-files
    pStart, pEnd: dword;    // points for search
    TxtVar: string;     // Vars as plain text
    XmlVar: TXMLDocument;   // var.xml
    uz: TUnZipper;      // for extract ZEF
    vName: string;      // name of Var
    i: integer;

{$R *.res}

    procedure Error(err: string);
    begin
        writeln(err + #13#10 + 'Press any key to exit.');
        ReadKey;
        halt;
    end;

    procedure SaveFile(Name: string);
    begin
        sl.Text := #239#187#191 + outText;
        try
            sl.SaveToFile(outPath + '\' + Name);
        except
            Error('Error: can''t save file ' + Name);
        end;
    end;

    function TxtExtract(TagOpen, TagClose: string): dword;
    var
        p1, p2: dword;
    begin
        txt := '';
        Result := 0;

        p1 := PosEx(TagOpen, xevText);
        if p1 = 0 then
            exit;
        // tab
        if (p1 > 1) and (xevText[p1 - 1] = #09) then
            p1 := p1 - 1;
        Result := p1;
        p2 := PosEx(TagClose, xevText, p1);
        if p2 = 0 then
            Error('Error: can''t find "' + TagClose + '"');
        p2 := p2 + Length(TagClose);
        // New line
        if (p2 + 2) >= Length(xevText) then
            if (xevText[p2 + 1] = #13) and (xevText[p2 + 2] = #10) then
                p2 := p2 + 2;

        txt := MidStr(xevText, p1, p2 - p1);
        Delete(xevText, p1, p2 - p1);
    end;

    procedure SymbolsReplace;
    var
        p1: dword;
    begin
        // >
        p1 := posex('&gt;', stTxt);
        while p1 <> 0 do
        begin
            stTxt[p1] := '>';
            Delete(stTxt, p1 + 1, 3);
            p1 := posex('&gt;', stTxt, p1);
        end;
        // <
        p1 := posex('&lt;', stTxt);
        while p1 <> 0 do
        begin
            stTxt[p1] := '<';
            Delete(stTxt, p1 + 1, 3);
            p1 := posex('&lt;', stTxt, p1);
        end;
        // &
        p1 := posex('&amp;', stTxt);
        while p1 <> 0 do
        begin
            Delete(stTxt, p1 + 1, 4);
            p1 := posex('&amp;', stTxt, p1);
        end;
        // '
        p1 := posex('&apos;', stTxt);
        while p1 <> 0 do
        begin
            stTxt[p1] := '''';
            Delete(stTxt, p1 + 1, 5);
            p1 := posex('&apos;', stTxt, p1);
        end;
        // "
        p1 := posex('&quot;', stTxt);
        while p1 <> 0 do
        begin
            stTxt[p1] := '"';
            Delete(stTxt, p1 + 1, 5);
            p1 := posex('&quot;', stTxt, p1);
        end;
    end;

    function StExtract: dword;
    var
        p1, p1s, p2: dword;
    begin
        Result := 0;
        p1 := PosEx('<FBProgram name="', txt);
        while p1 <> 0 do
        begin
            p2 := PosEx('"', txt, p1 + 17);
            if p2 = 0 then
                exit;
            if (p1 + 100) < p2 then
                exit;
            progName := MidStr(txt, p1 + 17, p2 - p1 - 17);

            p1s := PosEx('<STSource>', txt, p1 + 17) + 10;
            if p1s = 0 then
                exit;
            p2 := PosEx('</STSource>', txt, p1);
            if p2 = 0 then
                exit;
            stTxt := MidStr(txt, p1s, p2 - p1s);

            SymbolsReplace;
            p2 := PosEx('</FBProgram>', txt, p1) + 12;
            if p2 < 13 then
                exit;

            outText := stTxt;
            SaveFile(fbName + '\' + progName + '.st');
            Delete(txt, p1, p2 - p1);

            p1 := PosEx('<FBProgram name="', txt);
        end;
    end;

    procedure ProgExtract;
    var
        p1, p2: dword;
        TaskName: string;
        NonST: boolean;
        SR: string;
    begin
        // program name
        p1 := PosEx(' name="', txt);
        if p1 = 0 then
            Error('Error: can''t find name=');
        p1 := p1 + 7;
        p2 := PosEx('"', txt, p1);
        if p2 = 0 then
            Error('Error: can''t find end of program name');
        progName := MidStr(txt, p1, p2 - p1);

        // is SR
        p1 := PosEx(' type="', txt, p2);
        if p1 = 0 then
            Error('Error: can''t find type=');
        p1 := p1 + 7;
        p2 := PosEx('"', txt, p1);
        if p2 = 0 then
            Error('Error: can''t find end of program type name');
        SR := '';
        if MidStr(txt, p1, p2 - p1) = 'SR' then
            SR := '\SR';

        // task name
        p1 := PosEx(' task="', txt, p2);
        if p1 = 0 then
            Error('Error: can''t find task=');
        p1 := p1 + 7;
        p2 := PosEx('"', txt, p1);
        if p2 = 0 then
            Error('Error: can''t find end of task name');
        TaskName := MidStr(txt, p1, p2 - p1);
        if not DirectoryExists(outPath + '\' + TaskName) then
            CreateDir(outPath + '\' + TaskName);
        if SR <> '' then
            if not DirectoryExists(outPath + '\' + TaskName + '\SR') then
                CreateDir(outPath + '\' + TaskName + '\SR');

        // st text
        p1 := PosEx('<STSource>', txt, p2);
        NonST := (p1 = 0);
        if NonST then
        begin
            outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
            SaveFile(TaskName + SR + '\' + progName + '.xml');
            exit;
        end;
        p1 := p1 + 10;
        p2 := PosEx('</STSource>', txt, p1);
        if p2 = 0 then
            Error('Error: can''t find end of <STSource>');
        stTxt := MidStr(txt, p1, p2 - p1);
        Delete(txt, p1, p2 - p1);
        SymbolsReplace;
        outText := stTxt;
        SaveFile(TaskName + SR + '\' + progName + '.st');
        outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
        SaveFile(TaskName + SR + '\' + progName + '.xml');
    end;

    procedure ParceXmlVar(Node: TDOMNode; bName: string);
    var
        sname: string;      // structured long name
        NodeAttrib: string; // attributes
        tmp: string;
        i: integer;
        done: boolean;
    begin
        if Node = nil then
            Exit;
        done := False;
        sname := bName;
        // root vars
        if (node.NodeName = 'variables') and node.HasAttributes then
        begin
            for i := 0 to Node.Attributes.Length - 1 do
                if node.Attributes[i].NodeName = 'name' then
                    sname := node.Attributes[i].NodeValue;
        end;
        // Child vars
        if (node.NodeName = 'instanceElementDesc') and node.HasAttributes then
        begin
            for i := 0 to Node.Attributes.Length - 1 do
                if node.Attributes[i].NodeName = 'name' then
                begin
                    tmp := node.Attributes[i].NodeValue;
                    if length(tmp) > 0 then
                        if tmp[1] <> '[' then
                            tmp := '.' + tmp;
                    sname := sname + tmp;
                end;
            TxtVar := TxtVar + #9 + sname + #13#10;
            done := True;
        end;
        // values of child vars
        if node.NodeName = 'value' then
        begin
            TxtVar := TxtVar + #9#9 + 'val = ' + Trim(Node.TextContent) + #13#10;
            done := True;
        end;
        // comments
        if node.NodeName = 'comment' then
        begin
            TxtVar := TxtVar + #9'(* ' + Trim(Node.TextContent) + ' *)'#13#10;
            done := True;
        end;
        // etc
        if not done then
        begin
            if node.ParentNode <> nil then
                if node.ParentNode.ParentNode <> nil then
                    if (node.ParentNode.ParentNode.ParentNode <> nil) and (node.NodeName <> '#text') then
                        TxtVar := TxtVar + #9;

            NodeAttrib := '';
            if Node.HasAttributes then
                for i := 0 to Node.Attributes.Length - 1 do
                    with Node.Attributes[i] do
                        NodeAttrib := NodeAttrib + format(' %s="%s"', [NodeName, NodeValue]);
            NodeAttrib := Trim(NodeAttrib);

            if (node.NodeName <> 'dataBlock') and (node.NodeName <> '#text') then
                TxtVar := TxtVar + Trim(Node.NodeName + ' ' + NodeAttrib + Node.NodeValue) + #13#10;
        end;
        if node <> nil then
            Node := Node.FirstChild;
        while Node <> nil do
        begin
            ParceXmlVar(Node, sname);
            Node := Node.NextSibling;
        end;
    end;

begin
    if Paramcount = 0 then
        Error('Give me a ZEF-file or a XEF-file!');
    if LowerCase(ParamStr(1)) = 'sources' then
    begin
        rsSources := TResourceStream.Create(HINSTANCE, 'SOURCES', RT_RCDATA);
        try
            rsSources.SaveToFile('zef_splitter sources.zip');
        finally
            FreeAndNil(rsSources);
        end;
        exit;
    end;

    if (LowerCase(ParamStr(1)) = '/v') or (LowerCase(ParamStr(1)) = 'v') or (LowerCase(ParamStr(1)) = '-v') then
    begin
        writeln('ZEF splitter version 0.6');
        halt;
    end;

    if length(ParamStr(1)) < 5 then
        Error('Give me a ZEF-file or a XEF-file!');
    if (LowerCase(RightStr(ParamStr(1), 4)) <> '.zef') and (LowerCase(RightStr(ParamStr(1), 4)) <> '.xef') then
        Error('Give me a ZEF-file or a XEF-file!');

    zevPath := ExtractFileDir(ParamStr(1));
    zevName := ExtractFileName(ParamStr(1));
    if LowerCase(RightStr(zevName, 3)) = 'xef' then
        outPath := LeftStr(zevName, Length(zevName) - 4) + '_XEF'
    else
        outPath := LeftStr(zevName, Length(zevName) - 4) + '_ZEF';
    if zevPath <> '' then
        outPath := zevPath + '\' + outPath;

    // delete old
    if DirectoryExistsUTF8(outPath) then
    begin
        DeleteDirectory(outPath + '\MAST', False);
        DeleteDirectory(outPath + '\FAST', False);
        DeleteDirectory(outPath + '\DDT', False);
        DeleteDirectory(outPath + '\DTM', False);
        DeleteDirectory(outPath + '\FBT', False);
        DeleteDirectory(outPath + '\AUX0', False);
        DeleteDirectory(outPath + '\AUX1', False);
        DeleteDirectory(outPath + '\AUX2', False);
        DeleteDirectory(outPath + '\AUX3', False);
    end;

    // extract and load
    sl := TStringList.Create;
    if LowerCase(RightStr(zevName, 3)) = 'xef' then
        try
            sl.LoadFromFile(ParamStr(1));
        except
            Error('File read error');
        end
    else
    begin
        uz := TUnZipper.Create;
        uz.OutputPath := outPath;
        try
            uz.FileName := ParamStr(1);
            uz.Examine;
            uz.UnZipAllFiles;
            sl.LoadFromFile(outPath + '\unitpro.xef');
            DeleteFileUTF8(outPath + '\unitpro.xef');
        except
            Error('File read error');
        end;
        FreeAndNil(uz);
    end;
    xevText := sl.Text;

    if not DirectoryExists(outPath) then
        CreateDir(outPath);
    if not DirectoryExists(outPath + '\DDT') then
        CreateDir(outPath + '\DDT');
    if not DirectoryExists(outPath + '\FBT') then
        CreateDir(outPath + '\FBT');

    // var
    TxtExtract('<dataBlock>', '</dataBlock>');
    outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
    SaveFile('var.xml');

    // IOConf
    if TxtExtract('<IOConf>', '</IOConf>') = 0 then
        Error('Error: can''t find "<IOConf>"');
    outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
    SaveFile('IOConf.xml');

    // DDT
    pStart := TxtExtract('<DDTSource', '</DDTSource>');
    while pStart > 0 do
    begin
        pStart := posex('DDTName="', txt);
        if pStart = 0 then
            Error('Error: can''t find "DDTName="');
        pStart := pStart + 9;
        pEnd := posex('"', txt, pStart);
        if (pEnd = 0) or (pStart + 100 < pEnd) or (pStart = pEnd) then
            Error('Error: can''t find end of "DDTName="');
        outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
        SaveFile('DDT\' + MidStr(txt, pStart, pEnd - pStart) + '.xml');
        pStart := TxtExtract('<DDTSource', '</DDTSource>');
    end;

    // EFSource
    efTxt := '';
    pStart := TxtExtract('<EFSource', '</EFSource>');
    while pStart > 0 do
    begin
        efTxt := efTxt + #13#10 + txt;
        pStart := TxtExtract('<EFSource', '</EFSource>');
    end;
    outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + efTxt;
    SaveFile('EFSource.xml');

    // EFBSource
    efbTxt := '';
    pStart := TxtExtract('<EFBSource', '</EFBSource>');
    while pStart > 0 do
    begin
        efbTxt := efbTxt + #13#10 + txt;
        pStart := TxtExtract('<EFBSource', '</EFBSource>');
    end;
    outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + efbTxt;
    SaveFile('EFBSource.xml');

    // FBT
    pStart := TxtExtract('<FBSource', '</FBSource>');
    while pStart > 0 do
    begin
        pStart := posex('nameOfFBType="', txt);
        if pStart = 0 then
            Error('Error: can''t find "nameOfFBType="');
        pStart := pStart + 14;
        pEnd := posex('"', txt, pStart);
        if (pEnd = 0) or (pStart + 100 < pEnd) or (pStart = pEnd) then
            Error('Error: can''t find end of "nameOfFBType="');
        fbName := 'FBT\' + MidStr(txt, pStart, pEnd - pStart);
        if not DirectoryExists(outPath + '\' + fbName) then
            CreateDir(outPath + '\' + fbName);

        StExtract;
        outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
        SaveFile(fbName + '\' + RightStr(fbName, Length(fbName) - 4) + '.xml');
        pStart := TxtExtract('<FBSource', '</FBSource>');
    end;

    // comm
    TxtExtract('<comm>', '</comm>');
    outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
    SaveFile('comm.xml');

    // logicConf
    TxtExtract('<logicConf>', '</logicConf>');
    outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + #13#10 + txt;
    SaveFile('logicConf.xml');

    // tasks
    pStart := TxtExtract('<program', '</program>');
    while pStart > 0 do
    begin
        ProgExtract;
        pStart := TxtExtract('<program', '</program>');
    end;

    // etc
    pStart := posex(#13#10#13#10#13#10, xevText);
    while pStart <> 0 do
    begin
        Delete(xevText, pStart, 2);
        pStart := posex(#13#10#13#10#13#10, xevText);
    end;
    outText := xevText;
    SaveFile('etc.xml');

    // sorted var
    try
        sl.LoadFromFile(outPath + '\var.xml');
    except
        error('Error loadind var.xml');
    end;
    sl.Delete(sl.Count - 1);
    sl.Delete(0);
    sl.Delete(0);
    txt := sl.Text;
    sl.Clear;
    pStart := posex(#9#9'<variables name="', txt);
    while pStart <> 0 do
    begin
        pEnd := posex('"', txt, pStart + 19);
        if pEnd = 0 then
            error('Error extract var name');
        vName := MidStr(txt, pStart + 19, pEnd - pStart - 19);
        pEnd := posex('</variables>', txt, pStart + 20);
        if pEnd = 0 then
            error('Error: no end of var ' + vname);
        sl.Append(vname + hexStr(pStart, 8) + hexStr(pEnd + 12, 8));
        pStart := posex(#9#9'<variables name="', txt, pEnd + 12);
    end;
    sl.Sort;
    outText := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'#13#10;
    outText := outText + #9'<dataBlock>'#13#10;
    for i := 0 to sl.Count - 1 do
    begin
        if length(sl.Strings[i]) < 16 then
            error('Strange sort error');
        try
            pStart := Hex2Dec( leftstr(RightStr(sl.Strings[i], 16), 8) );
            pEnd := Hex2Dec( RightStr(sl.Strings[i], 8) );
        except on e:exception do
            error('Sort error: ' + e.Message);
        end;
        outText := outText + MidStr(txt, pStart, pEnd - pStart) + #13#10;
    end;
    outText := outText + #9'</dataBlock>'#13#10;
    SaveFile('var_sorted.xml');

    // save var as text
    try
        ReadXMLFile(XmlVar, outPath + '\var_sorted.xml');
    except
        error('Error: can''t read var.xml');
    end;
    TxtVar := '';
    ParceXmlVar(XmlVar.DocumentElement, '');
    outText := TxtVar;
    SaveFile('var.txt');

    FreeAndNil(sl);
end.
