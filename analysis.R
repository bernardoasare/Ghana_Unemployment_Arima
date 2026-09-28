# ==============================================================================
# Statistical Analysis of Unemployment Trends in Ghana (1994-2024)
# Regression + Box-Jenkins ARIMA forecasting
# Author: Asare Bernard Odarno
# ==============================================================================
# Run from the project root:  Rscript analysis.R
# Required packages: tseries, forecast, car, lmtest, ggplot2

suppressPackageStartupMessages({
  library(tseries)   # adf.test
  library(forecast)  # Arima, forecast, checkresiduals
  library(car)       # vif
  library(lmtest)    # dwtest
  library(ggplot2)
})

dir.create("figures", showWarnings = FALSE)
dir.create("outputs", showWarnings = FALSE)

# ---- 1. Load data ------------------------------------------------------------
# Rates in the CSV are decimals (0.059 = 5.9%). The ARIMA series is modelled in
# percent, so the unemployment column is multiplied by 100 for that part only.
data <- read.csv("data/ghana_unemployment_1994_2024.csv")
stopifnot(nrow(data) == 31)

# ---- 2. Descriptive statistics (Table 4.1) ------------------------------------
desc <- data.frame(
  Variable = names(data)[-1],
  N    = nrow(data),
  Mean = sapply(data[-1], mean),
  SD   = sapply(data[-1], sd),
  row.names = NULL
)
print(desc)
write.csv(desc, "outputs/table_4.1_descriptive_statistics.csv", row.names = FALSE)

# ---- 3. Multiple regression (Tables 4.2 - 4.6) --------------------------------
fit <- lm(Unemployment_Rate ~ GDP_Growth + Inflation_Rate +
            Population + Population_Growth_Rate, data = data)
print(summary(fit))
cat("\nVIF:\n");  print(vif(fit))
cat("\nDurbin-Watson:\n"); print(dwtest(fit))
capture.output(summary(fit), vif(fit), dwtest(fit),
               file = "outputs/regression_results.txt")

# ---- 4. Time series and stationarity (Tables 4.8 - 4.10) ----------------------
vv.ts <- ts(data$Unemployment_Rate * 100, start = 1994, frequency = 1)

png("figures/fig_4.1_unemployment_time_series.png", width = 1600, height = 800, res = 200)
plot(vv.ts, type = "b", lty = 3, pch = 1, col = "red",
     main = "Ghana Unemployment Rate, 1994-2024",
     xlab = "Year", ylab = "Unemployment Rate (%)")
dev.off()

cat("\nADF - level:\n");             print(adf.test(vv.ts))
vv.diff <- diff(vv.ts)
cat("\nADF - first difference:\n");  print(adf.test(vv.diff))
vv.diff2 <- diff(vv.ts, differences = 2)
cat("\nADF - second difference:\n"); print(adf.test(vv.diff2))

# ---- 5. Model identification (Figure 4.2) -------------------------------------
png("figures/fig_4.2_acf_pacf.png", width = 1800, height = 800, res = 200)
par(mfrow = c(1, 2))
acf(vv.diff2,  main = "ACF - second differenced series")
pacf(vv.diff2, main = "PACF - second differenced series")
dev.off()

# ---- 6. Model comparison (Table 4.11) -----------------------------------------
orders <- list(c(0,2,1), c(0,2,2), c(1,2,1), c(1,2,2))
models <- lapply(orders, function(o) Arima(vv.ts, order = o))
comparison <- data.frame(
  Model = sapply(orders, function(o) sprintf("ARIMA(%d,%d,%d)", o[1], o[2], o[3])),
  AIC = sapply(models, AIC),
  BIC = sapply(models, BIC)
)
print(comparison)
write.csv(comparison, "outputs/table_4.11_model_comparison.csv", row.names = FALSE)

# ---- 7. Selected model and diagnostics (Tables 4.12 - 4.14) -------------------
best_model <- Arima(vv.ts, order = c(0, 2, 2))
print(summary(best_model))

# Ljung-Box as reported by checkresiduals(): lag 6, df 4
print(Box.test(residuals(best_model), lag = 6, type = "Ljung-Box", fitdf = 2))

png("figures/fig_4.3_residual_diagnostics.png", width = 1800, height = 1200, res = 200)
checkresiduals(best_model)
dev.off()

# ---- 8. Forecast 2025-2029 (Table 4.15, Figure 4.4) ---------------------------
fc <- forecast(best_model, h = 5)
print(fc)

fc_table <- data.frame(
  Year = 2025:2029,
  Point_Forecast = as.numeric(fc$mean),
  Lower_80 = fc$lower[, 1], Upper_80 = fc$upper[, 1],
  Lower_95 = fc$lower[, 2], Upper_95 = fc$upper[, 2]
)
write.csv(fc_table, "outputs/table_4.15_forecast_2025_2029.csv", row.names = FALSE)

# Improved forecast plot: labelled axis; unemployment cannot be negative, so the
# displayed intervals are floored at 0 (the table keeps the raw model values).
hist_df <- data.frame(Year = 1994:2024, Rate = as.numeric(vv.ts))
fc_plot <- transform(fc_table,
  Lower_80 = pmax(Lower_80, 0), Lower_95 = pmax(Lower_95, 0))

p <- ggplot() +
  geom_ribbon(data = fc_plot, aes(Year, ymin = Lower_95, ymax = Upper_95),
              fill = "#9db7e8", alpha = 0.5) +
  geom_ribbon(data = fc_plot, aes(Year, ymin = Lower_80, ymax = Upper_80),
              fill = "#4a76c9", alpha = 0.5) +
  geom_line(data = hist_df, aes(Year, Rate), linewidth = 0.8) +
  geom_line(data = fc_plot, aes(Year, Point_Forecast), colour = "#1f3f8f", linewidth = 1) +
  labs(title = "Ghana Unemployment Rate: ARIMA(0,2,2) Forecast, 2025-2029",
       subtitle = "Shaded bands: 80% and 95% prediction intervals (floored at 0%)",
       x = "Year", y = "Unemployment Rate (%)") +
  theme_minimal(base_size = 12)
ggsave("figures/fig_4.4_arima_forecast.png", p, width = 8, height = 4.5, dpi = 200)

cat("\nDone. Tables in outputs/, figures in figures/.\n")
