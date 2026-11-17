# Integrate+ marteloscopes: GBIF records

Fetched, not committed. `python scripts/import/import_marteloscopes.py fetch` reads the
occurrences of the Klosterwald, Rosskopf and Mooswald marteloscopes from the GBIF dataset
*Spatially explicit database of tree related microhabitats (TreMs)*
([10.15468/ocof3v](https://doi.org/10.15468/ocof3v)) into `gbif/<plot>.json`: one record per
tree with its measurements (DBH, height, living/dead, microhabitat codes with counts) and the
local x/y from the verbatim record.

Licence: CC BY 4.0. Cite the dataset when using the data (the citation is stored in each file
and on the campaign).
