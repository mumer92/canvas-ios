// @flow

import { Reducer, Action, combineReducers } from 'redux'
import { handleActions } from 'redux-actions'
import CourseListActions from './actions'
import CourseSettingsActions from './settings/actions'
import handleAsync from '../../utils/handleAsync'
import { parseErrorMessage } from '../../redux/middleware/error-handler'
import groupCustomColors from '../../api/utils/group-custom-colors'
import fromPairs from 'lodash/fromPairs'
import { tabs } from './tabs/tabs-reducer'
import { assignmentGroups } from '../assignments/assignment-group-refs-reducer'
import { enrollments } from '../enrollments/enrollments-refs-reducer'
import { refs as quizzes } from '../quizzes/list/reducer'

// dummy's to appease combineReducers
const course = (state) => (state || {})
const color = (state) => (state || '#FFFFFF00')
const pending = (state) => (state || 0)
const error = (state) => (state || null)

const courseContents: Reducer<CourseState, Action> = combineReducers({
  course,
  color,
  tabs,
  assignmentGroups,
  oldColor: color,
  pending,
  error,
  enrollments,
  quizzes,
})

const { refreshCourses, updateCourseColor } = CourseListActions
const { updateCourse } = CourseSettingsActions

export const defaultState: { [courseID: string]: CourseState & CourseContentState } = {}

const emptyCourseState: CourseContentState = {
  tabs: { pending: 0, tabs: [] },
  assignmentGroups: { pending: 0, refs: [] },
  enrollments: { pending: 0, refs: [] },
  quizzes: { pending: 0, refs: [] },
}

export const normalizeCourse = (course: Course, colors: { [courseId: string]: string } = {}, prevState: CourseContentState = emptyCourseState): CourseState => {
  const { id } = course
  const color = colors[(id || 'none')] || '#ffc100'
  return {
    ...prevState,
    course,
    color,
    pending: 0,
  }
}

const coursesData: Reducer<CoursesState, any> = handleActions({
  [refreshCourses.toString()]: handleAsync({
    resolved: (state, { result: [coursesResponse, colorsResponse] }) => {
      const colors = groupCustomColors(colorsResponse.data).custom_colors.course
      const courses = coursesResponse.data
      const newStates = courses.map((course) => {
        return [course.id, normalizeCourse(course, colors, state[course.id])]
      })
      return fromPairs(newStates)
    },
  }),
  [updateCourseColor.toString()]: handleAsync({
    pending: (state, { courseID, color }) => {
      return {
        ...state,
        [courseID]: {
          ...state[courseID],
          color,
          oldColor: state[courseID].color,
          pending: state[courseID].pending + 1,
        },
      }
    },
    resolved: (state, { courseID }) => {
      let courseState = { ...state[courseID] }
      delete courseState.oldColor
      courseState.pending--
      return {
        ...state,
        [courseID]: courseState,
      }
    },
    rejected: (state, { courseID, error }) => {
      let courseState = { ...state[courseID] }
      courseState.color = courseState.oldColor
      delete courseState.oldColor
      courseState.pending--
      return {
        ...state,
        [courseID]: courseState,
      }
    },
  }),
  [updateCourse.toString()]: handleAsync({
    pending: (state, { course }) => {
      return {
        ...state,
        [course.id]: {
          ...state[course.id],
          course,
          pending: state[course.id].pending + 1,
        },
      }
    },
    resolved: (state, { result, course }) => {
      return {
        ...state,
        [course.id]: {
          ...state[course.id],
          pending: state[course.id].pending - 1,
          error: null,
        },
      }
    },
    rejected: (state, { oldCourse, error }) => {
      return {
        ...state,
        [oldCourse.id]: {
          ...state[oldCourse.id],
          course: oldCourse,
          error: parseErrorMessage(error),
          pending: state[oldCourse.id].pending - 1,
        },
      }
    },
  }),
}, defaultState)

export function courses (state: CoursesState = defaultState, action: Action): CoursesState {
  let newState = state
  if (action.payload && action.payload.courseID) {
    const courseID = action.payload.courseID
    const currentCourseState: CourseState = state[courseID]
    const courseState = courseContents(currentCourseState, action)
    newState = {
      ...state,
      [courseID]: courseState,
    }
  }
  return coursesData(newState, action)
}
