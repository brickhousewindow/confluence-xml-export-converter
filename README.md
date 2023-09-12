# confluence-xml-export-converter

## Usage
### Requirements
Besides having Perl installed the following modules must be installed (package manager or cpanminus):
- XML::LibXML
- YAML::XS
- File::Slurp
- MIME::Base64
- MIME::Types
- HTML::Entities

### Converting to YAML
Run the script xml_to_yml.pl inside the unpacked XML export folder. The file entities.xml and the folder attachments must be present. The output goes to the STDIN, redirect it to a file.
Example:
`perl xml_to_yml.pl >export.yml`

Then run the next script to create an importable set of files for the application.
Example for wikijs:
`cat export.yml | perl towikijs.pl`
