
http://formation-perl.fr/guide-perl-08.html
https://perldoc.perl.org/perlre.html

## MARC vs CSV ou TSV

Si l'export est en CSV ou TSV ou JSON, vous devez mapper les champs que vous retenez et dire ceux que vous gardez dans le fichier. Pour n export MARC, pas besoin d'ajouter ces lignes

Ainsi un fix qui n'est pas pour MARC ressemblera à:

### Mappage des champs

```
marc_map(001, 'id')
marc_map(995k, 'cote')
```
### Rétention dans le fichier d'export

```
retain(id,cote)
```

## CSV d'exemple obtenu

```
cote,id
"525.5 BEA525.5 BEA",2
"152.4 DUV",196
"796.522 DUT",276
"523.5 MET",293
"520 WAL",660
"752 VAR",788
"520 CHA",1047
```
