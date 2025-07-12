// Contact Form Handling
document.addEventListener('DOMContentLoaded', function() {
    const contactForm = document.getElementById('contact-form');
    
    if (contactForm) {
        contactForm.addEventListener('submit', function(e) {
            e.preventDefault();
            
            // Get form data
            const formData = new FormData(this);
            const data = Object.fromEntries(formData);
            
            // Basic validation
            if (!data.name || !data.email || !data.subject || !data.message) {
                alert('Please fill in all required fields.');
                return;
            }
            
            // Email validation
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(data.email)) {
                alert('Please enter a valid email address.');
                return;
            }
            
            // Simulate form submission
            const submitBtn = this.querySelector('button[type="submit"]');
            const originalText = submitBtn.innerHTML;
            
            submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Sending...';
            submitBtn.disabled = true;
            
            // Simulate API call
            setTimeout(() => {
                alert('Thank you for your message! We will get back to you within 24 hours.');
                this.reset();
                submitBtn.innerHTML = originalText;
                submitBtn.disabled = false;
            }, 2000);
        });
    }
});

// Contact Form Validation and Handling
const contactForm = document.getElementById('contact-form');

contactForm.addEventListener('submit', (e) => {
    e.preventDefault();
    
    // Get form data
    const formData = new FormData(contactForm);
    const name = formData.get('name');
    const email = formData.get('email');
    const phone = formData.get('phone');
    const subject = formData.get('subject');
    const message = formData.get('message');
    const newsletter = formData.get('newsletter');
    
    // Validate form
    if (!validateForm(name, email, subject, message)) {
        return;
    }
    
    // Show success message
    showSuccessMessage();
    
    // Reset form
    contactForm.reset();
    
    // Here you would typically send the form data to your server
    console.log('Form submitted:', {
        name,
        email,
        phone,
        subject,
        message,
        newsletter: newsletter ? 'Yes' : 'No'
    });
});

// Form Validation Function
function validateForm(name, email, subject, message) {
    let isValid = true;
    
    // Clear previous error messages
    clearErrorMessages();
    
    // Validate name
    if (!name || name.trim().length < 2) {
        showError('name', 'Please enter your full name (minimum 2 characters)');
        isValid = false;
    }
    
    // Validate email
    if (!email || !isValidEmail(email)) {
        showError('email', 'Please enter a valid email address');
        isValid = false;
    }
    
    // Validate subject
    if (!subject) {
        showError('subject', 'Please select a subject');
        isValid = false;
    }
    
    // Validate message
    if (!message || message.trim().length < 10) {
        showError('message', 'Please enter a message (minimum 10 characters)');
        isValid = false;
    }
    
    return isValid;
}

// Email Validation Helper
function isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

// Show Error Message
function showError(fieldId, message) {
    const field = document.getElementById(fieldId);
    const errorDiv = document.createElement('div');
    errorDiv.className = 'error-message';
    errorDiv.textContent = message;
    errorDiv.style.cssText = `
        color: #dc3545;
        font-size: 0.875rem;
        margin-top: 0.25rem;
        display: block;
    `;
    
    field.parentNode.appendChild(errorDiv);
    field.style.borderColor = '#dc3545';
}

// Clear Error Messages
function clearErrorMessages() {
    const errorMessages = document.querySelectorAll('.error-message');
    errorMessages.forEach(error => error.remove());
    
    const formFields = document.querySelectorAll('.form-group input, .form-group select, .form-group textarea');
    formFields.forEach(field => {
        field.style.borderColor = '#ddd';
    });
}

// Show Success Message
function showSuccessMessage() {
    const successMessage = document.createElement('div');
    successMessage.className = 'success-message';
    successMessage.innerHTML = `
        <div style="
            background: #d4edda;
            color: #155724;
            padding: 1rem;
            border-radius: 8px;
            margin-bottom: 1rem;
            border: 1px solid #c3e6cb;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        ">
            <i class="fas fa-check-circle"></i>
            <span>Thank you for your message! We'll get back to you within 24 hours.</span>
        </div>
    `;
    
    contactForm.parentNode.insertBefore(successMessage, contactForm);
    
    // Remove success message after 5 seconds
    setTimeout(() => {
        if (successMessage.parentNode) {
            successMessage.parentNode.removeChild(successMessage);
        }
    }, 5000);
}

// FAQ Functionality
const faqItems = document.querySelectorAll('.faq-item');

faqItems.forEach(item => {
    const question = item.querySelector('.faq-question');
    
    question.addEventListener('click', () => {
        // Close other FAQ items
        faqItems.forEach(otherItem => {
            if (otherItem !== item) {
                otherItem.classList.remove('active');
            }
        });
        
        // Toggle current FAQ item
        item.classList.toggle('active');
    });
});

// Real-time Form Validation
const formFields = document.querySelectorAll('#contact-form input, #contact-form select, #contact-form textarea');

formFields.forEach(field => {
    field.addEventListener('blur', () => {
        validateField(field);
    });
    
    field.addEventListener('input', () => {
        // Clear error when user starts typing
        const errorMessage = field.parentNode.querySelector('.error-message');
        if (errorMessage) {
            errorMessage.remove();
            field.style.borderColor = '#ddd';
        }
    });
});

// Validate Individual Field
function validateField(field) {
    const value = field.value.trim();
    const fieldId = field.id;
    
    // Clear previous error for this field
    const existingError = field.parentNode.querySelector('.error-message');
    if (existingError) {
        existingError.remove();
    }
    
    // Validate based on field type
    switch (fieldId) {
        case 'name':
            if (!value || value.length < 2) {
                showError('name', 'Please enter your full name (minimum 2 characters)');
            }
            break;
        case 'email':
            if (!value || !isValidEmail(value)) {
                showError('email', 'Please enter a valid email address');
            }
            break;
        case 'subject':
            if (!value) {
                showError('subject', 'Please select a subject');
            }
            break;
        case 'message':
            if (!value || value.length < 10) {
                showError('message', 'Please enter a message (minimum 10 characters)');
            }
            break;
    }
}

// Character Counter for Message
const messageField = document.getElementById('message');
const messageCounter = document.createElement('div');
messageCounter.className = 'message-counter';
messageCounter.style.cssText = `
    font-size: 0.875rem;
    color: #666;
    text-align: right;
    margin-top: 0.25rem;
`;

messageField.parentNode.appendChild(messageCounter);

messageField.addEventListener('input', () => {
    const length = messageField.value.length;
    const maxLength = 1000;
    messageCounter.textContent = `${length}/${maxLength} characters`;
    
    if (length > maxLength * 0.9) {
        messageCounter.style.color = '#dc3545';
    } else if (length > maxLength * 0.7) {
        messageCounter.style.color = '#ffc107';
    } else {
        messageCounter.style.color = '#666';
    }
});

// Initialize character counter
messageField.dispatchEvent(new Event('input'));

// Auto-resize textarea
messageField.addEventListener('input', function() {
    this.style.height = 'auto';
    this.style.height = (this.scrollHeight) + 'px';
});

// Contact Form Animation
const contactFormElement = document.querySelector('.contact-form');

// Add animation when form comes into view
const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, {
    threshold: 0.1
});

// Observe contact form
contactFormElement.style.opacity = '0';
contactFormElement.style.transform = 'translateY(30px)';
contactFormElement.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
observer.observe(contactFormElement);

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// Business Hours Animation
const hoursSchedule = document.querySelector('.hours-schedule');
const hoursDays = document.querySelectorAll('.hours-day');

// Add staggered animation to business hours
hoursDays.forEach((day, index) => {
    day.style.opacity = '0';
    day.style.transform = 'translateX(-20px)';
    day.style.transition = `opacity 0.6s ease ${index * 0.1}s, transform 0.6s ease ${index * 0.1}s`;
});

const hoursObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            hoursDays.forEach(day => {
                day.style.opacity = '1';
                day.style.transform = 'translateX(0)';
            });
        }
    });
}, {
    threshold: 0.1
});

hoursObserver.observe(hoursSchedule);

// Contact Cards Animation
const contactCards = document.querySelectorAll('.contact-card');

contactCards.forEach((card, index) => {
    card.style.opacity = '0';
    card.style.transform = 'translateY(30px)';
    card.style.transition = `opacity 0.6s ease ${index * 0.2}s, transform 0.6s ease ${index * 0.2}s`;
});

const contactObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            contactCards.forEach(card => {
                card.style.opacity = '1';
                card.style.transform = 'translateY(0)';
            });
        }
    });
}, {
    threshold: 0.1
});

contactObserver.observe(document.querySelector('.contact-grid'));

// Form Field Focus Effects
formFields.forEach(field => {
    field.addEventListener('focus', () => {
        field.parentNode.style.transform = 'scale(1.02)';
        field.parentNode.style.transition = 'transform 0.2s ease';
    });
    
    field.addEventListener('blur', () => {
        field.parentNode.style.transform = 'scale(1)';
    });
});

// Newsletter Checkbox Enhancement
const newsletterCheckbox = document.getElementById('newsletter');
const checkboxLabel = document.querySelector('.checkbox-label');

newsletterCheckbox.addEventListener('change', () => {
    if (newsletterCheckbox.checked) {
        checkboxLabel.style.color = '#fd7e14';
        checkboxLabel.style.fontWeight = '600';
    } else {
        checkboxLabel.style.color = '#666';
        checkboxLabel.style.fontWeight = '400';
    }
});

// Add loading state to submit button
const submitButton = contactForm.querySelector('button[type="submit"]');

contactForm.addEventListener('submit', () => {
    submitButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Sending...';
    submitButton.disabled = true;
    
    // Simulate form submission delay
    setTimeout(() => {
        submitButton.innerHTML = 'Send Message';
        submitButton.disabled = false;
    }, 2000);
}); 