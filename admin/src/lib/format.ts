// 한국 포맷 유틸

const won = new Intl.NumberFormat('ko-KR')

export function formatWon(amount: number | null | undefined): string {
  if (amount == null) return '-'
  return `₩${won.format(amount)}`
}

export function formatPoint(amount: number | null | undefined): string {
  if (amount == null) return '-'
  return `${won.format(amount)}P`
}

export function formatNumber(n: number | null | undefined): string {
  if (n == null) return '-'
  return won.format(n)
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '-'
  const d = new Date(iso)
  if (isNaN(d.getTime())) return '-'
  return new Intl.DateTimeFormat('ko-KR', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d)
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '-'
  const d = new Date(iso)
  if (isNaN(d.getTime())) return '-'
  return new Intl.DateTimeFormat('ko-KR', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(d)
}

export function formatPhone(phone: string | null | undefined): string {
  if (!phone) return '-'
  const d = phone.replace(/\D/g, '')
  if (d.length === 11) return `${d.slice(0, 3)}-${d.slice(3, 7)}-${d.slice(7)}`
  if (d.length === 10) return `${d.slice(0, 3)}-${d.slice(3, 6)}-${d.slice(6)}`
  return phone
}
