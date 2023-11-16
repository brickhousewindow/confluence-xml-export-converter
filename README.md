# confluence-xml-export-converter

## UTF8 handling
Truth to be told the UTF8 handling works but is not solid. It does not work correctly after the conversion to markdown inside the script "to_wikijs". Therefor the user is warned that the export might contain errors and strange symbols.

## Usage
### Requirements
Besides having Perl installed the following modules must be installed (package manager or cpanminus):
- XML::LibXML
- YAML::XS
- MIME::Base64
- MIME::Types
- HTML::Entities

### Converting to YAML
Run the script xml_to_yml.pl inside the unpacked XML export folder. The file entities.xml and the folder attachments must be present. The output goes to the STDIN, redirect it to a file.
Example:
`perl xml_to_yml.pl >export.yml`

Then run the next script to create an importable set of files for the application. Expects that the file is named export.yml. This is currently necessary because of UTF8 handling.
Example for wikijs:
`perl towikijs.pl`

## Intermediate yaml
The script xml_to_yml.pl outputs the space structure contained inside a yaml file. The structure already contains the space tree compared to the flat xml export. Optionaly all attachments from inside the attachments folder are include inside the yaml file base64 encoded. This is enabled using the "-a" flag.
