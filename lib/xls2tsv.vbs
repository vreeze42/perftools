if WScript.Arguments.Count < 2 Then
    WScript.Echo "Error! Please specify the source path and the destination. Usage: XlsToCsv SourcePath.xls Destination-basename"
    Wscript.Quit
End If
Dim oExcel
Set oExcel = CreateObject("Excel.Application")
Dim oBook
Set oBook = oExcel.Workbooks.Open(Wscript.Arguments.Item(0))
'oBook.SaveAs WScript.Arguments.Item(1), 6
'WScript.Echo "oBook.ActiveSheet = " + oBook.ActiveSheet.Name 
const xlTSV = 21 ' 3-11-2012: code 3 werkt mogelijk ook.

'oBook2.SaveAs WScript.Arguments.Item(1), 21

dim sht
for each sht in oBook.worksheets
 sht.activate
 dim output_filename
 output_filename = WScript.Arguments.Item(1) & "_" & replace( sht.name, " ", "_" ) & ".tsv"
 oBook.saveAs output_filename, xlTSV
next

oBook.Close False
oExcel.Quit
'WScript.Echo "Done"

