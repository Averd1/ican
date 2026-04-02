import pandas as pd
import plotly.express as px

file = "your_file.csv"
df = pd.read_csv(file)

# IMU
fig = px.line(df, y=["ax","ay","az"], title="IMU Acceleration")
fig.show()

# Distance
fig2 = px.line(df, y=["dist_left","dist_right"], title="Distance Sensors")
fig2.show()

# Light
fig3 = px.line(df, y=["lux"], title="Ambient Light")
fig3.show()

# Heart
fig4 = px.line(df, y=["heart"], title="Heart Signal")
fig4.show()

# Mode
fig5 = px.line(df, y=["mode"], title="System Mode")
fig5.show()