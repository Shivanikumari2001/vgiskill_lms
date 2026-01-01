<template>
	<div class="flex h-full flex-col relative">
		<div class="h-full pb-20" id="scrollContainer">
			<slot />
		</div>

		<!-- Dropdown menu -->
		<div
			class="fixed bottom-16 right-2 w-[80%] rounded-md bg-surface-white text-base p-5 space-y-4 shadow-md z-40"
			v-if="showMenu"
			ref="menu"
		>
			<div
				v-for="link in otherLinks"
				:key="link.label"
				class="flex items-center space-x-2 cursor-pointer"
				@click="handleClick(link)"
			>
				<component
					:is="icons[link.icon]"
					class="h-4 w-4 stroke-1.5 text-ink-gray-5"
				/>
				<div>{{ link.label }}</div>
			</div>
		</div>

		<!-- Fixed menu with all 7 icons - Always visible -->
		<div
			class="fixed bottom-0 left-0 right-0 w-full flex items-center justify-around border-t border-outline-gray-2 bg-surface-white standalone:pb-4 z-50 shadow-lg"
			style="min-height: 60px; display: flex !important; visibility: visible !important;"
		>
			<button
				v-for="tab in footerLinks"
				:key="tab.label"
				class="flex flex-col items-center justify-center py-3 px-2 transition active:scale-95 flex-1"
				@click="handleFooterClick(tab)"
			>
				<component
					:is="icons[tab.icon]"
					class="h-6 w-6 stroke-1.5"
					:class="[isActive(tab) ? 'text-ink-gray-9' : 'text-ink-gray-5']"
				/>
			</button>
		</div>
	</div>
</template>
<script setup>
import { getSidebarLinks } from '@/utils'
import { useRouter } from 'vue-router'
import { call } from 'frappe-ui'
import { watch, ref, onMounted } from 'vue'
import { sessionStore } from '@/stores/session'
import { useSettings } from '@/stores/settings'
import { usersStore } from '@/stores/user'
import * as icons from 'lucide-vue-next'

const { logout, user } = sessionStore()
let { isLoggedIn } = sessionStore()
const { sidebarSettings, settings } = useSettings()
const router = useRouter()
let { userResource } = usersStore()
const sidebarLinks = ref(getSidebarLinks())
const otherLinks = ref([])
const showMenu = ref(false)
const menu = ref(null)
const isModerator = ref(false)
const isInstructor = ref(false)

// Fixed footer links with all 7 icons
const footerLinks = ref([
	{
		label: 'Courses',
		icon: 'BookOpen',
		to: 'Courses',
		activeFor: ['Courses', 'CourseDetail', 'Lesson', 'CourseForm', 'LessonForm'],
	},
	{
		label: 'Batches',
		icon: 'Users',
		to: 'Batches',
		activeFor: ['Batches', 'BatchDetail', 'Batch', 'BatchForm'],
	},
	{
		label: 'Certifications',
		icon: 'GraduationCap',
		to: 'CertifiedParticipants',
		activeFor: ['CertifiedParticipants'],
	},
	{
		label: 'Jobs',
		icon: 'Briefcase',
		to: 'Jobs',
		activeFor: ['Jobs', 'JobDetail'],
	},
	{
		label: 'Statistics',
		icon: 'TrendingUp',
		to: 'Statistics',
		activeFor: ['Statistics'],
	},
	{
		label: 'Contact Us',
		icon: 'Mail',
		to: null, // Will be set based on settings
		isContactUs: true,
	},
	{
		label: 'Menu',
		icon: 'List',
		to: null,
		isMenu: true,
	},
])

onMounted(() => {
	// Ensure footer links are always initialized
	addOtherLinks()
	
	sidebarSettings.reload(
		{},
		{
			onSuccess(data) {
				filterLinksToShow(data)
				addOtherLinks()
			},
			onError() {
				// If settings fail to load, still show footer menu
				console.warn('Sidebar settings failed to load, footer menu will still be visible')
			},
		}
	)
	// Load settings for Contact Us
	settings.reload()
})

const handleOutsideClick = (e) => {
	if (menu.value && !menu.value.contains(e.target)) {
		showMenu.value = false
	}
}

watch(showMenu, (val) => {
	if (val) {
		setTimeout(() => {
			document.addEventListener('click', handleOutsideClick)
		}, 0)
	} else {
		document.removeEventListener('click', handleOutsideClick)
	}
})

const filterLinksToShow = (data) => {
	Object.keys(data).forEach((key) => {
		if (!parseInt(data[key])) {
			sidebarLinks.value = sidebarLinks.value.filter(
				(link) => link.label.toLowerCase().split(' ').join('_') !== key
			)
		}
	})
}

const addOtherLinks = () => {
	if (user) {
		otherLinks.value.push({
			label: 'Notifications',
			icon: 'Bell',
			to: 'Notifications',
		})
		otherLinks.value.push({
			label: 'Profile',
			icon: 'UserRound',
		})
		otherLinks.value.push({
			label: 'Log out',
			icon: 'LogOut',
		})
	} else {
		otherLinks.value.push({
			label: 'Log in',
			icon: 'LogIn',
		})
	}
}

watch(userResource, () => {
	if (userResource.data) {
		isModerator.value = userResource.data.is_moderator
		isInstructor.value = userResource.data.is_instructor
		addPrograms()
		if (isModerator.value || isInstructor.value) {
			addProgrammingExercises()
			addQuizzes()
			addAssignments()
		}
	}
})

const addQuizzes = () => {
	otherLinks.value.push({
		label: 'Quizzes',
		icon: 'CircleHelp',
		to: 'Quizzes',
	})
}

const addAssignments = () => {
	otherLinks.value.push({
		label: 'Assignments',
		icon: 'Pencil',
		to: 'Assignments',
	})
}

const addProgrammingExercises = () => {
	otherLinks.value.push({
		label: 'Programming Exercises',
		icon: 'Code',
		to: 'ProgrammingExercises',
	})
}

const addPrograms = async () => {
	let canAddProgram = await checkIfCanAddProgram()
	if (!canAddProgram) return
	let activeFor = ['Programs', 'ProgramDetail']
	let index = 1

	sidebarLinks.value.splice(index, 0, {
		label: 'Programs',
		icon: 'Route',
		to: 'Programs',
		activeFor: activeFor,
	})
}

const checkIfCanAddProgram = async () => {
	if (isModerator.value || isInstructor.value) {
		return true
	}
	const programs = await call('lms.lms.utils.get_programs')
	return programs.enrolled.length > 0 || programs.published.length > 0
}

let isActive = (tab) => {
	if (tab.isMenu || tab.isContactUs) return false
	return tab.activeFor?.includes(router.currentRoute.value.name)
}

const handleClick = (tab) => {
	if (tab.label == 'Log in') window.location.href = '/login'
	else if (tab.label == 'Log out')
		logout.submit().then(() => {
			isLoggedIn = false
		})
	else if (tab.label == 'Profile')
		router.push({
			name: 'Profile',
			params: {
				username: userResource.data?.username,
			},
		})
	else router.push({ name: tab.to })
}

const handleFooterClick = (tab) => {
	if (tab.isMenu) {
		toggleMenu()
		return
	}
	if (tab.isContactUs) {
		// Handle Contact Us - can be URL or email
		const contactUrl = settings.data?.contact_us_url
		const contactEmail = settings.data?.contact_us_email
		if (contactUrl) {
			window.open(contactUrl, '_blank')
		} else if (contactEmail) {
			window.location.href = `mailto:${contactEmail}`
		}
		return
	}
	if (tab.to) {
		router.push({ name: tab.to })
	}
}

const isVisible = (tab) => {
	if (tab.label == 'Log in') return !isLoggedIn
	else if (tab.label == 'Log out') return isLoggedIn
	else return true
}

const toggleMenu = () => {
	showMenu.value = !showMenu.value
}
</script>
