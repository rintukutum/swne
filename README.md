# swne
Similarity Weighted Nonnegative Embedding (SWNE), a method for visualizing high dimensional datasets

## Installation instructions

1. Install devtools with `install.packages("devtools")` if not already installed
2. Install liger with `devtools::install_github("JEFworks/liger")`
3. Install swne with `devtools::install_github("yanwu2014/swne")`

## Usage
We highly recommend using SWNE with either Seurat (http://satijalab.org/seurat/) or Pagoda2 (https://github.com/hms-dbmi/pagoda2), two general single cell RNA-seq analysis pipelines. 

For a quick example using the pbmc dataset from the Seurat walkthrough, see pbmc3k_swne.R under the Scripts directory.
The pre-calculated Seurat object is also in that directory.
