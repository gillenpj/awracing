# awracing

Statistical models of UK All-Weather racing outcomes, built on the 
Smartform database in R.

## Papers

**Paper 1: Replicating Owen (2019) on UK All-Weather Flat handicaps, 2006–2015**  
Replicates the conditional-logit win model of Alun Owen on UK All-Weather 
handicap races at Kempton, Lingfield, Southwell and Wolverhampton, 2006–2015. 
The model trails the betting market on both scoring rules — a finding that 
motivates the extended feature set and tree-based alternatives in papers 2 and 3.  
[Read online](https://gillenpj.github.io/awracing/paper1/) | [PDF](https://gillenpj.github.io/awracing/paper1/index.pdf)

## Stack

R 4.6, targets, mlogit, tidyverse, Quarto. Data: Smartform MySQL database.

## Reproducibility

`targets::tar_make()` from the project root rebuilds all pipeline targets 
and re-renders the paper. Requires a local Smartform database and a `.env` 
file with connection credentials (not committed).
