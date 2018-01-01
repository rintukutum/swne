## NMF functions

# x and y can be vectors or doubles
.kl_div <- function(x, y, pseudocount = 1e-12) {
  x <- x + pseudocount; y <- y + pseudocount;
  stopifnot(length(x) == length(y))
  return(x*log(x/y) - x + y)
}


FindComponents <- function(A, k.range = seq(1,10,1), alpha = 0, n.cores = 1, do.plot = T, seed = NULL,
                           na.frac = 0.3, loss = "mse", max.iter = 1000) {
  if (!is.null(seed)) { set.seed(seed) }
  A <- as.matrix(A)

  ind <- sample(length(A), na.frac*length(A));
  A2 <- A;
  A2[ind] <- NA;

  A.ind <- A[ind]
  err <- sapply(k.range, function(k) {
    z <- NNLM::nnmf(A2, k, alpha = c(alpha, alpha, 0), n.threads = n.cores, verbose = 0, loss = loss)
    A_hat <- with(z, W %*% H)
    mse  <- mean((A_hat[ind] - A.ind)^2)
    mkl <- mean(kl_div(A.ind, A_hat[ind]))
    return(c(mse, mkl))
  })

  if (loss == "mse") { j <- 1; } else { j <- 2; }
  min.idx <- which.min(err[j,]);

  if (do.plot) {
    plot(k.range, err[1,], col = "blue", type = 'b', main = "MSE");
    plot(k.range, err[2,], col = "red", type = 'b', main = "MKL");
  }

  res <- list()
  res$err <- err
  res$k <- k.range[[min.idx]]

  return(res)
}


## NMF initialization
.pos <- function(x) { as.numeric(x >= 0) * x }

.neg <- function(x) { - as.numeric(x < 0) * x }

.norm <- function(x) { sqrt(drop(crossprod(x))) }

.nnsvd_init <- function(A, k, LINPACK = F) {
  if( any(A < 0) ) stop('The input matrix contains negative elements !')

  size <- dim(A);
  m <- size[1]; n <- size[2];

  W <- matrix(0, m, k);
  H <- matrix(0, k, n);

  #1st SVD --> partial SVD rank-k to the input matrix A.
  s = svd(A, k, k, LINPACK = LINPACK);
  U <- s$u; S <- s$d; V <- s$v

  #choose the first singular triplet to be nonnegative
  W[,1] = sqrt(S[1]) * abs(U[,1]);
  H[1,] = sqrt(S[1]) * abs(t(V[,1]));

  # second SVD for the other factors (see table 1 in Boutsidis' paper)
  for( i in seq(2,k) ) {
    uu = U[,i]; vv = V[,i];
    uup = .pos(uu); uun = .neg(uu) ;
    vvp = .pos(vv); vvn = .neg(vv);
    n_uup = .norm(uup);
    n_vvp = .norm(vvp) ;
    n_uun = .norm(uun) ;
    n_vvn = .norm(vvn) ;
    termp = n_uup %*% n_vvp; termn = n_uun %*% n_vvn;
    if (termp >= termn) {
      W[,i] = sqrt(S[i] * termp) * uup / n_uup;
      H[i,] = sqrt(S[i] * termp) * vvp / n_vvp;
    } else {
      W[,i] = sqrt(S[i] * termn) * uun / n_uun;
      H[i,] = sqrt(S[i] * termn) * vvn / n_vvn;
    }
  }

  #actually these numbers are zeros
  W[W < 0.0000000001] <- 0;
  H[H < 0.0000000001] <- 0;

  ind1 <- W == 0; ind2 <- H == 0;
  n1 <- sum(ind1); n2 <- sum(ind2);
  A.mean <- mean(A);
  W[ind1] <-  runif(n1, min = 0, max = A.mean) / 100
  H[ind2] <-  runif(n2, min = 0, max = A.mean) / 100

  return(list(W = W, H = H))
}



.ica_init <- function(A, k) {
  ica.res <- ica::icafast(t(A), nc = k)
  nmf.init <- list(W = ica.res$M, H = t(ica.res$S))

  A.mean <- mean(A)
  nmf.init$W[nmf.init$W < 0.0000000001] <- 0; nmf.init$H[nmf.init$H < 0.0000000001] <- 0;
  zero.idx.w <- which(nmf.init$W == 0); zero.idx.h <- which(nmf.init$H == 0);

  nmf.init$W[zero.idx.w] <- runif(length(zero.idx.w), 0, A.mean/100)
  nmf.init$H[zero.idx.h] <- runif(length(zero.idx.h), 0, A.mean/100)

  return(nmf.init)
}


RunNMF <- function(A, k, alpha = 0, init = "random", n.cores = 1, loss = "mse", n.rand.init = 5) {
  if (!init %in% c("ica", "nnsvd", "random")) {
    stop("Invalid initialization method")
  }

  A <- as.matrix(A)
  if (any(A < 0)) { stop("Input matrix has negative values") }
  A.mean <- mean(A)

  if (init == "ica") {
    nmf.init <- .ica_init(A, k)
  } else if (init == "nnsvd") {
    nmf.init <- .nnsvd_init(A, k, LINPACK = T)
  } else {
    nmf.init <- NULL
  }


  if(is.null(nmf.init)) {
    nmf.res.list <- lapply(1:n.rand.init, function(i) nnmf(A, k = k, alpha = alpha, init = nmf.init,
                                                           n.threads = n.cores, loss = loss, verbose = F))
    err <- sapply(nmf.res.list, function(x) tail(x[[loss]], n = 1))
    nmf.res <- nmf.res.list[[which.min(err)]]
  } else {
    nmf.res <- NNLM::nnmf(A, k = k, alpha = alpha, init = nmf.init, n.threads = n.cores, loss = loss)
  }

  colnames(nmf.res$W) <- rownames(nmf.res$H) <- sapply(1:ncol(nmf.res$W), function(i) paste("metagene", i, sep = "_"))
  return(list(nmf.loadings = nmf.res$W, nmf.scores = nmf.res$H))
}


ProjectNMF <- function(newdata, loadings, alpha = rep(0,3), init= NULL, loss = "mkl") {
  lm.out <- NNLM::nnlm(loadings, newdata, alpha = alpha, init = init, loss = loss)
  return(lm.out$coefficients)
}