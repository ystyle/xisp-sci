import { defineConfig } from 'vitepress'

export default defineConfig({
  title: '星枢科学计算',
  description: 'xisp-sci —— 建在星枢 Xisp 之上的科学计算套件',
  lang: 'zh-CN',
  base: '/xisp-sci/',
  outDir: '../docs/dist',
  lastUpdated: true,
  themeConfig: {
    nav: [
      { text: '指南', link: '/guide/01-quickstart' },
      { text: '实战', link: '/cookbook/iris' },
      { text: 'API 参考', link: '/api/' },
      { text: '设计与性能', link: '/reference/design' },
      { text: '星枢 Xisp', link: 'https://ystyle.github.io/xisp/' },
    ],
    sidebar: {
      '/guide/': [
        {
          text: '入门',
          items: [
            { text: '快速开始', link: '/guide/01-quickstart' },
            { text: '数组：一切的基础', link: '/guide/02-arrays' },
            { text: '读数据：CSV 与缺失值', link: '/guide/03-data-io' },
          ],
        },
        {
          text: '分析',
          items: [
            { text: '描述统计', link: '/guide/04-stats' },
            { text: '分组与假设检验', link: '/guide/05-inference' },
            { text: '回归：从相关到预测', link: '/guide/06-regression' },
          ],
        },
        {
          text: '计算',
          items: [
            { text: '线性代数', link: '/guide/07-linalg' },
            { text: '信号处理', link: '/guide/08-signal' },
            { text: '数值方法', link: '/guide/09-numeric' },
          ],
        },
      ],
      '/cookbook/': [
        {
          text: '实战',
          items: [
            { text: 'Iris：十分钟入门', link: '/cookbook/iris' },
            { text: '教师工作流：成绩能预测吗', link: '/cookbook/teacher' },
            { text: '图表数据：交给前端渲染', link: '/cookbook/charts' },
          ],
        },
      ],
      '/api/': [
        {
          text: 'API 参考',
          items: [
            { text: '总览', link: '/api/' },
            { text: '数组 array', link: '/api/array' },
            { text: '数据 IO', link: '/api/io' },
            { text: '统计 stats', link: '/api/stats' },
            { text: '线性代数 linalg', link: '/api/linalg' },
            { text: '信号 signal', link: '/api/signal' },
            { text: '数值方法 num', link: '/api/num' },
          ],
        },
      ],
      '/reference/': [
        {
          text: '参考',
          items: [
            { text: '设计取舍', link: '/reference/design' },
            { text: '性能与基准', link: '/reference/performance' },
            { text: '成员与发布', link: '/reference/members' },
          ],
        },
      ],
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/ystyle/xisp-sci' },
    ],
    footer: {
      message: 'MIT License',
      copyright: '星枢科学计算 · 建在星枢 Xisp 之上',
    },
    search: { provider: 'local' },
  },
})
