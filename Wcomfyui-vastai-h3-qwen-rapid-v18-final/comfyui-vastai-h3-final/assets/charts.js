(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();

  // --- Mermaid ---
  if (window.mermaid) {
    mermaid.initialize({ startOnLoad: true, theme: 'neutral', securityLevel: 'loose' });
  }

  // --- Chart: 显存占用 vs GPU 档位 ---
  var el = document.getElementById('chart-vram');
  if (el && window.echarts) {
    var chart = echarts.init(el, null, { renderer: 'svg' });
    chart.setOption({
      animation: false,
      tooltip: {
        trigger: 'axis',
        appendToBody: true,
        axisPointer: { type: 'shadow' }
      },
      grid: { left: 10, right: 70, top: 30, bottom: 30, containLabel: true },
      xAxis: {
        type: 'value',
        name: 'GB',
        nameTextStyle: { color: muted },
        axisLabel: { color: muted },
        splitLine: { lineStyle: { color: rule } }
      },
      yAxis: {
        type: 'category',
        data: ['图像编辑\nQwen-Edit-2511 FP8', '首尾帧视频\nWan2.2 I2V FP8'],
        axisLabel: { color: ink, fontSize: 12, lineHeight: 17 },
        axisLine: { lineStyle: { color: rule } },
        axisTick: { show: false }
      },
      series: [{
        type: 'bar',
        barWidth: 46,
        data: [
          { value: 28, itemStyle: { color: accent, borderRadius: [0, 8, 8, 0] } },
          { value: 40, itemStyle: { color: accent2, borderRadius: [0, 8, 8, 0] } }
        ],
        label: {
          show: true, position: 'right', color: ink, fontWeight: 700,
          formatter: function (p) { return '约 ' + p.value + ' GB 峰值'; }
        },
        markLine: {
          symbol: 'none',
          animation: false,
          label: { color: muted, fontSize: 11, formatter: '{b}', position: 'insideEndTop' },
          lineStyle: { type: 'dashed', width: 1.5 },
          data: [
            { xAxis: 24, name: '24GB(4090)', lineStyle: { color: '#d64545' } },
            { xAxis: 48, name: '48GB(A6000/L40S)', lineStyle: { color: accent } },
            { xAxis: 80, name: '80GB(A100)', lineStyle: { color: muted } }
          ]
        }
      }]
    });
    window.addEventListener('resize', function () { chart.resize(); });
  }
})();
