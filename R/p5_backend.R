# p5_backend.R
# Paper 5 — the compute backend, captured at fit time.
#
# The backend is a frozen parameter of this paper: every rung is fitted on
# the CPU libtorch build, and results do not reproduce across backends, so a
# rung fitted on one backend cannot be compared with a rung fitted on
# another. `renv.lock` pins R packages, not the C++ runtime, so nothing in
# version control records which build is present.
#
# This file closes that gap. `p5_capture_backend()` is called BOTH as its
# own target and inside every fitting function, so a fitted run carries the
# backend it was actually produced on. A report that reads the run cannot
# claim a backend the fit did not use.

#' Capture the compute backend
#'
#' @return A one-row tibble: torch and libtorch versions, whether CUDA and
#'   cuDNN are available, the device in use, and the CPU thread count.
p5_capture_backend <- function() {
  cuda <- isTRUE(try(torch::cuda_is_available(), silent = TRUE))
  tibble::tibble(
    device = if (cuda) "cuda" else "cpu",
    cuda_is_available = cuda,
    cudnn_is_available = isTRUE(try(torch::backends_cudnn_is_available(),
                                    silent = TRUE)),
    torch_version = as.character(utils::packageVersion("torch")),
    libtorch_version = as.character(
      get("torch_version", asNamespace("torch"))
    ),
    torch_threads = as.integer(torch::torch_get_num_threads()),
    r_version = paste0(R.version$major, ".", R.version$minor),
    platform = R.version$platform
  )
}

#' Assert that a set of fitted runs was produced on the recorded backend
#'
#' Compares the backend each run carries with the backend captured now, on
#' the fields that change results: the device, the torch and libtorch
#' versions, and the thread count.
#'
#' @param runs A list of fitted runs, each carrying a `backend` tibble.
#' @param backend The backend tibble to check them against.
#' @return `backend`, invisibly, with an `n_runs_checked` column added.
p5_assert_backend <- function(runs, backend) {
  fields <- c("device", "cuda_is_available", "torch_version",
              "libtorch_version", "torch_threads")
  recorded <- purrr::map(runs, function(r) {
    stopifnot(!is.null(r$backend))
    as.list(r$backend[fields])
  })
  expected <- as.list(backend[fields])
  ok <- purrr::map_lgl(recorded, function(x) identical(x, expected))
  if (!all(ok)) {
    stop("Fitted runs carry a different backend than the one recorded: ",
         "run(s) ", paste(which(!ok), collapse = ", "))
  }
  dplyr::mutate(backend, n_runs_checked = length(runs))
}
