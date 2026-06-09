import { use, graphic } from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, GraphicComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import VChart from 'vue-echarts'

use([LineChart, GridComponent, TooltipComponent, GraphicComponent, CanvasRenderer])

export { graphic }
export default VChart
