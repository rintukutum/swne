## Geneset handling functions

#' Load genesets from gmt file. For more info on the .gmt file format, see [link]
#'
#' @param geneset.file Geneset filename
#'
#' @return List of genesets (character vectors)
#'
#' @export
#'
ReadGenesets <- function(genesets.file) {
  genesets <- as.list(readLines(genesets.file))
  genesets <- lapply(genesets, function (v) strsplit(v, '\t')[[1]])
  geneset.names <- unlist(lapply(genesets, function(x) x[[1]]))
  genesets <- lapply(genesets, function(v) v[3:length(v)])
  names(genesets) <- sapply(geneset.names, function(x) gsub(" ", "_", x))
  return(genesets)
}


## Helper function for filtering genesets
.clean_genesets <- function(genesets, min.size = 5, max.size = 500, annot = FALSE) {
  genesets <- as.list(genesets)
  size <- unlist(lapply(genesets, length))
  genesets <- genesets[size > min.size & size < max.size]
  return(genesets)
}


#' Filters genesets according to minimum and maximum set size
#'
#' @param gene.names Name of all genes to use
#' @param min.size Minimum geneset size
#' @param max.size Maximum geneset size
#'
#' @return Filtered list of genesets
#'
#' @export
#'
FilterGenesets <- function(genesets, gene.names, min.size = 5, max.size = 500) {
  genesets <- lapply(genesets, function (x) return(x[x %in% gene.names]))
  genesets <- .clean_genesets(genesets, min.size = min.size, max.size = max.size)
  return(genesets)
}


#' Writes genesets to gmt file
#'
#' @param genesets List of genesets
#' @param file.name Name of output file
#'
#' @return Writes to file
#'
#' @export
#'
WriteGenesets <- function(genesets, file.name) {
  genesets <- lapply(names(genesets), function(name) {x <- genesets[[name]]; x <- c(name,name,x); return(x);})
  n.cols <- 1.5*max(unlist(lapply(genesets, length)))
  empty <- lapply(genesets, write, file.name, append=TRUE, ncolumns = n.cols, sep = '\t')
}


## Functions for annotating NMF factors

## Creates a genes x genesets indicator matrix
.genesets_indicator <- function(genesets, inv = F, return.numeric = F) {
  genes <- unique(unlist(genesets, F, F))

  ind <- matrix(F, length(genes), length(genesets))
  rownames(ind) <- genes
  colnames(ind) <- names(genesets)

  for (i in 1:length(genesets)) {
    ind[genesets[[i]], i] <- T
  }

  if(inv) {
    ind <- !ind
  }

  if (return.numeric) {
    ind.numeric <- apply(ind, 2, function(x) as.numeric(x))
    rownames(ind.numeric) <- rownames(ind)
    return(ind.numeric)
  } else {
    return(ind)
  }
}


#' Creates a clusters x cells indicator matrix where a 1 means the cell belongs to that cluster
#'
#' @param clusters Cell clusters
#' @return clusters x cells indicator matrix
#'
ClusterIndicatorMatrix <- function(clusters) {
  clusters.list <- UnflattenGroups(clusters)
  return(t(.genesets_indicator(clusters.list, return.numeric = T)))
}


#' Projects dataset onto genesets using either NMF or a nonnegative linear model
#'
#' @param norm.counts Normalized input data
#' @param genesets List of genesets to use
#' @param method Method used to project data onto genesets. lm uses a simple linear model while mf
#'               will use a masked version of nmf.
#' @param loss Loss function for the nonnegative linear model
#' @param n.cores Number of cores to use
#'
#' @return List of gene loadings and factor scores, with each factor corresponding to a geneset
#'
#' @export
#'
ProjectGenesets <- function(norm.counts, genesets, method = "lm", loss = "mse", n.cores = 1) {
  if (!method %in% c("lm", "mf")) { stop("Invalid method") }

  if (method == "lm") {
    full.genesets.matrix <- .genesets_indicator(genesets, inv = F, return.numeric = T)
    genesets.H <- ProjectSamples(norm.counts[rownames(full.genesets.matrix),], full.genesets.matrix,
                                  loss = loss, n.cores = n.cores)
  } else if (method == "mf") {
    genesets.mask <- .genesets_indicator(genesets, inv = T)
    nmf.res <- NNLM::nnmf(as.matrix(norm.counts[rownames(genesets.mask),]), k = ncol(genesets.mask), loss = loss,
                          mask = list(W = genesets.mask), n.threads = n.cores)
    colnames(nmf.res$W) <- rownames(nmf.res$H) <- colnames(genesets.mask)
  }

  return(nmf.res)
}


#' Calculate geneset factor loadings from gene factor loadings
#'
#' @param W gene factor loadings from NMF
#' @param W.genesets.project gene factor loadings from projecting genesets onto data
#' @param top.genesets List of genesets to calculate loadings for
#'
#' @return Matrix of geneset by factor loadings
#'
#' @export
#'
CalcGenesetLoadings <- function(W, W.genesets.project, top.genesets) {
  genesets.weights <- lapply(names(top.genesets), function(name) {
    genes <- genesets[[name]]
    weights <- W.genesets.project[genes, name]; names(weights) <- genes;
    weights
  }); names(genesets.weights) <- names(top.genesets);

  weighted.genesets <- lapply(genesets.weights, function(x) x/sum(x))
  genesets.loadings <- apply(W, 2, function(x) {
    sapply(names(top.genesets), function(name) {
      genes <- genesets[[name]]
      genes.weights <- genesets.weights[[name]]
      mean(x[genes] * genes.weights)
    })
  })
  return(genesets.loadings)
}


#' Find the top gene or geneset markers for each NMF factor using pearson/spearman correlation,
#' or mutual information
#'
#' @param feature.mat Feature matrix (features x samples)
#' @param H Factor scores (factors x samples)
#' @param n.cores Number of cores to use
#' @param metric Association metric: pearson, spearman, or IC (information coefficient)
#'
#' @return Features x factors matrix of associations or correlations
#'
#' @import snow
#' @export
#'
FactorAssociation <- function(feature.mat, nmf.scores, n.cores = 8, metric = "IC") {
  cl <- snow::makeCluster(n.cores, type = "SOCK")
  snow::clusterExport(cl, c("nmf.scores", "MutualInf"), envir = environment())
  if (metric == "IC") {
    source.log <- snow::parLapply(cl, 1:length(cl), function(i) library(MASS))
    assoc <- t(snow::parApply(cl, feature.mat, 1, function(v) apply(nmf.scores, 1, function(u) MutualInf(u, v))))
  } else if (metric == "pearson") {
    assoc <- t(snow::parApply(cl, feature.mat, 1, function(v) apply(nmf.scores, 1, function(u) cor(u, v))))
  } else if (metric == "spearman") {
    assoc <- t(snow::parApply(cl, feature.mat, 1, function(v) apply(nmf.scores, 1, function(u) cor(u, v, method = "spearman"))))
  } else {
    stop("Invalid correlation metric")
  }
  stopCluster(cl)

  rownames(assoc) <- rownames(feature.mat)
  colnames(assoc) <- rownames(nmf.scores)
  return(assoc)
}


#' Summarize the factors x features association matrix into a readable dataframe
#'
#' @param feature.factor.assoc (features x factors) association matrix from FactorAssociation
#' @param features.return Number of top features to return for each factor
#' @param features.use Only consider a subset of features. Default is NULL, which will use all features
#'
#' @return Dataframe summarizing top features for each factor
#'
#' @export
#'
SummarizeAssocFeatures <- function(feature.factor.assoc, features.return = 10, features.use = NULL) {
  if (!is.null(features.use)) {
    feature.factor.assoc <- feature.factor.assoc[features.use,]
  }

  factor.features.df <- do.call("rbind", lapply(1:ncol(feature.factor.assoc), function(i) {
    features.df <- data.frame(assoc_score = feature.factor.assoc[,i])
    features.df$feature <- rownames(feature.factor.assoc)
    features.df$factor <- colnames(feature.factor.assoc)[[i]]
    features.df <- features.df[order(features.df$assoc_score, decreasing = T),]
    head(features.df, n = features.return)
  }))

  rownames(factor.features.df) <- NULL
  return(factor.features.df)
}


#' Runs GSEA on the gene association coefficients for each NMF
#'
#' @param gene.factor.assoc Matrix with the gene associations for each nmf
#' @param genesets Genesets to use (as a named list)
#' @param power GSEA coefficient power
#' @param n.rand Number of permutations to use when calculating significance
#' @param n.cores Number of threads to use
#'
#' @return Dataframe summarizing the gsea results
#'
#' @import liger
#'
#' @export
#'
RunGSEA <- function(gene.factor.assoc, genesets, power = 1, n.rand = 1000, n.cores = 1) {
  nmfs <- colnames(gene.factor.assoc)
  gsea.list <- lapply(nmfs, function(nf) {
    gene.assocs <- gene.factor.assoc[,nf]
    gene.assocs <- sort(gene.assocs, decreasing = T)
    df <- liger::bulk.gsea(gene.assocs, genesets, power = power, n.rand = n.rand, mc.cores = n.cores)
    df$geneset <- rownames(df); df$nmf <- nf;
    df
  })

  gsea.df <- do.call("rbind", gsea.list); rownames(gsea.df) <- NULL;
  gsea.df
}


#' Compute Information Coefficient [IC]
#' Pablo Tamayo Dec 30, 2015
#'
#' @param x Input vector x
#' @param y Input vector y
#' @param n.grid Gridsize for calculating IC
#'
#' @return Mutual information between x and y
#'
#' @export
#'
MutualInf <-  function(x, y, n.grid = 25) {
  x.set <- !is.na(x)
  y.set <- !is.na(y)
  overlap <- x.set & y.set

  x <- x[overlap] +  0.000000001*runif(length(overlap))
  y <- y[overlap] +  0.000000001*runif(length(overlap))

  if (length(x) > 2) {
    delta = c(MASS::bcv(x), MASS::bcv(y))
    rho <- cor(x, y)
    rho2 <- abs(rho)
    delta <- delta*(1 + (-0.75)*rho2)
    kde2d.xy <- MASS::kde2d(x, y, n = n.grid, h = delta)
    FXY <- kde2d.xy$z + .Machine$double.eps
    dx <- kde2d.xy$x[2] - kde2d.xy$x[1]
    dy <- kde2d.xy$y[2] - kde2d.xy$y[1]
    PXY <- FXY/(sum(FXY)*dx*dy)
    PX <- rowSums(PXY)*dy
    PY <- colSums(PXY)*dx
    HXY <- -sum(PXY * log(PXY))*dx*dy
    HX <- -sum(PX * log(PX))*dx
    HY <- -sum(PY * log(PY))*dy
    PX <- matrix(PX, nrow=n.grid, ncol=n.grid)
    PY <- matrix(PY, byrow = TRUE, nrow=n.grid, ncol=n.grid)
    MI <- sum(PXY * log(PXY/(PX*PY)))*dx*dy
    IC <- sign(rho) * sqrt(1 - exp(- 2 * MI))
    if (is.na(IC)) IC <- 0
  } else {
    IC <- 0
  }
  return(IC)
}


## Genotype/group handling functions

#' Convert groups list to design matrix
#'
#' @param groups.list Named list of cell vectors for each genotype
#' @param max.groups Maximum number of genotypes per cell
#' @param min.cells Minumum number of cells per genotype
#' @param drop.cells Drop cells in genotypes that are filtered out
#'
#' @return Sparse binary matrix where rows are cells, and columns are genotypes. 1 means the cell received the genotype.
#'
#' @import Matrix
#' @import hash
#' @export
#'
DesignMatrix <- function(groups.list, max.groups = 2, min.cells = 5, drop.cells = T) {
  require(hash)
  cell.names <- unique(unlist(groups.list, F, F))
  single.groups <- names(groups.list)

  single.mat <- Matrix::Matrix(0, length(cell.names), length(single.groups), dimnames = list(cell.names, single.groups))
  for (i in 1:ncol(single.mat)) {
    single.mat[groups.list[[i]], i] <- 1
  }
  if (drop.cells) single.mat <- single.mat[Matrix::rowSums(single.mat) <= max.groups, ]
  n_cells_single <- Matrix::colSums(single.mat)
  single.mat <- single.mat[ ,names(n_cells_single[n_cells_single >= min.cells])]
  single.mat <- single.mat[Matrix::rowSums(single.mat) > 0, ]

  combo.rows <- single.mat[Matrix::rowSums(single.mat) > 1,]
  combo.groups <- unique(apply(combo.rows, 1, function(x) paste(names(x[x == 1]), collapse = ":", sep = "")))
  if (max.groups > 1 && length(combo.groups) > 0) {
    combo.groups.list <- hash::hash(keys = combo.groups)
    for (i in 1:nrow(combo.rows)) {
      mat.row <- combo.rows[i,]
      genotype <- paste(names(mat.row[mat.row == 1]), collapse = ":", sep = "")
      cell <- rownames(combo.rows)[[i]]
      combo.groups.list[[genotype]] <- c(combo.groups.list[[genotype]], cell)
    }
    combo.groups.list <- as.list(combo.groups.list)
    combo.groups.list[['keys']] <- NULL
    combo.groups.list <- combo.groups.list[combo.groups]

    combo.mat <- Matrix(0, nrow(single.mat), length(combo.groups), dimnames = list(rownames(single.mat), combo.groups))
    for (i in 1:ncol(combo.mat)) {
      combo.mat[combo.groups.list[[i]],i] <- 1
    }

    # Filter out combos that have too few cells
    n_cells_combo <- Matrix::colSums(combo.mat)
    combos_keep <- names(n_cells_combo[n_cells_combo >= min.cells])

    # Remove filtered combo cells from design matrix
    if (length(combos_keep) > 0) {
      combo.mat <- combo.mat[ ,combos_keep]
      design.mat <- cbind(single.mat, combo.mat)
      filtered.cells <- (Matrix::rowSums(single.mat) > 1) & (Matrix::rowSums(combo.mat) == 0)

    } else {
      design.mat <- single.mat
      filtered.cells <- (Matrix::rowSums(single.mat) > 1)

    }
    if (drop.cells) design.mat <- design.mat[!filtered.cells,]
  } else {
    design.mat <- single.mat
  }
  return(design.mat)
}

.single_groups <- function(groups.list, min.cells = 1) {
  groups.matrix <- DesignMatrix(groups.list, max.groups = 1, min.cells = min.cells)
  groups.list <- lapply(colnames(groups.matrix), function(g) {
    rownames(groups.matrix)[which(groups.matrix[,g] == 1)]
  })
  names(groups.list) <- colnames(groups.matrix)
  return(groups.list)
}

#' Convert list of sample groups into a flat vector.
#' Removes all samples belonging to multiple groups
#'
#' @param groups.list List of sample groups
#'
#' @return A character vector of the group each sample belongs to. The vector names are the sample names.
#'
#' @export
#'
FlattenGroups <- function(groups.list) {
  cell.names <- unlist(groups.list, F, F)
  if (length(cell.names) > length(unique(cell.names))) {
    print("Warning: removing all samples belonging to multiple groups")
    groups.list <- .single_groups(groups.list)
    cell.names <- unlist(groups.list, F, F)
  }

  groups <- rep(NA, length(cell.names))
  names(groups) <- cell.names
  for (g in names(groups.list)) {
    groups[groups.list[[g]]] <- g
  }

  if (any(is.na(groups))) { stop("Some unassigned cells"); }
  return(groups)
}


#' Converts a flat sample groups character vector into a list format
#'
#' @param groups Character vector of sample groups
#'
#' @return List of groups: each list element contains the samples for that group
#'
#' @export
#'
UnflattenGroups <- function(groups) {
  groups.list <- c()
  unique.groups <- unique(groups)
  for (g in unique.groups) {
    g.cells <- names(groups[groups == g])
    groups.list[[g]] <- g.cells
  }
  return(groups.list)
}


#' Read in sample groups from a csv file format
#'
#' @param groups.file Name of groups file
#' @param sep.char Delimiter
#'
#' @return List of groups
#'
#' @export
#'
ReadGroups <- function(groups.file, sep.char = ",") {
  group.data <- read.table(groups.file, sep = sep.char, header = F, stringsAsFactors = F)
  groups <- group.data[[1]]
  full.groups.list <- lapply(rownames(group.data), function(i) sapply(strsplit(group.data[i,2], split = ',')[[1]], trimws))
  full.groups.list <- lapply(full.groups.list, function(x) make.names(x))
  names(full.groups.list) <- groups
  return(full.groups.list)
}


#' Write sample groups from list to csv format
#'
#' @param groups.list List of groups
#' @param out.file Name of output file
#'
#' @export
#'
WriteGroups <- function(groups.list, out.file) {
  group.data <- sapply(groups.list, function(x) paste('\"', paste(x, collapse = ", "), '\"', sep = ""))
  group.data <- sapply(names(group.data), function(x) paste(x, group.data[[x]], sep = ","))
  fileConn = file(out.file)
  writeLines(group.data, fileConn)
  close(fileConn)
}


#### Misc utilities ####

#' Convert dataframe to matrix, specifying all column names
#'
#' @param df Dataframe
#' @param output.name Column of df to use as matrix values
#' @param row.col Column of df to use as matrix rows
#' @param col.col Column of df to use as matrix columns
#'
#' @return Matrix
#' @importFrom reshape2 acast
#' @export
#'
UnflattenDataframe <- function(df, output.name, row.col = 'Gene', col.col = 'Group') {
  df <- df[c(row.col, col.col, output.name)]
  colnames(df) <- c('row', 'column', output.name)
  mat.out <- reshape2::acast(df, row~column, value.var = output.name)
  return(mat.out)
}
