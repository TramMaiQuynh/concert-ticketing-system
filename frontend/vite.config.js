import react from '@vitejs/plugin-react'
import { defineConfig, loadEnv } from 'vite'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  return {
    plugins: [react()],
    server: {
      // Cho phép truy cập qua domain tunnel tạm thời (vd. *.trycloudflare.com) khi demo.
      // Chỉ dùng cho demo ngắn hạn, không bật mặc định cho môi trường phát triển thường.
      allowedHosts: env.VITE_ALLOW_TUNNEL_HOST ? true : undefined,
      proxy: {
        '/api': {
          target: env.VITE_API_PROXY_TARGET ?? 'http://localhost:5295',
          changeOrigin: true,
        },
      },
    },
  }
})
