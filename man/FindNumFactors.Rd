% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/nmf.R
\name{FindNumFactors}
\alias{FindNumFactors}
\title{Determines the optimal number of NMF factors to use via reconstruction error}
\usage{
FindNumFactors(A, k.range = seq(1, 10, 1), alpha = 0, n.cores = 1,
  do.plot = T, seed = NULL, na.frac = 0.3, loss = "mse",
  recon.err = "mse", max.iter = 1000)
}
\arguments{
\item{A}{Input data matrix}

\item{k.range}{Range of NMF factors to fit over}

\item{alpha}{Regularization parameter}

\item{n.cores}{Number of threads}

\item{do.plot}{Whether to plot the reconstruction error}

\item{seed}{Random seed for selecting missing data}

\item{na.frac}{Fraction of data to set as missing}

\item{loss}{Loss function to use for NMF}

\item{recon.err}{Error function to minimize}

\item{max.iter}{Maximum iterations for NMF run}
}
\value{
Reconstruction error at each number of NMF factors specified in k.range
}
\description{
Determines the optimal number of NMF factors to use via reconstruction error
}
