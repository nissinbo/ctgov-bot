
# Source existing parts
source("global.R")
source("ui.R")
source("server.R")

# Start the app
shinyApp(ui = ui, server = server)
