import { createRouter, createWebHashHistory } from '@ionic/vue-router';
import { RouteRecordRaw } from 'vue-router';
import HomePage from '../views/HomePage.vue'

const routes: Array<RouteRecordRaw> = [
  {
    path: '/',
    redirect: '/home'
  },
  {
    path: '/home',
    name: 'Home',
    component: HomePage
  }
]

const router = createRouter({
  // Hash routes need no server rewrite, so the same build runs on GitHub Pages and in the app.
  history: createWebHashHistory(),
  routes
})

export default router
