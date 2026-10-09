interface GripperLogoProps {
  className?: string;
}

// "G" ring whose crossbar ends in a two-prong charger plug. Stroke uses currentColor.
function GripperLogo({ className }: GripperLogoProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      <path d="M18.6 7.5A8 8 0 1 0 20 12h-4.5" />
      <path d="M15.5 9.5v5M15.5 10.75H13M15.5 13.25H13" />
    </svg>
  );
}

export default GripperLogo;
